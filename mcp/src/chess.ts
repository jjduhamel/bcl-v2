import { Chess, Move } from 'chess.js';

// Replay a UCI move log onto a fresh Chess instance. The contract's bitboard
// validates piece geometry but not chess rules (no check enforcement, castle-
// through-check allowed; see CLAUDE.md), so the log may contain moves that
// chess.js's public .move() would refuse. For those we fall back to chess.js's
// pseudo-legal generator + private _makeMove, mirroring the strategy in
// client/composables/useChessEngine.js (applyManually / applyCastleManually).
export function replayMoves(moves: string[]): Chess {
  const chess = new Chess();
  for (const uci of moves) {
    const move = chess.move(uci, { strict: false });
    if (move) continue;
    // chess.js rejected the move. Two cases:
    //   (a) bitboard-legal but chess-illegal (king-in-check, castle through
    //       check) — advance the board via pseudo-legal lookup.
    //   (b) bitboard-illegal too — applyManually is a no-op and the board
    //       stays where it was. Shouldn't happen on a log returned by the
    //       contract since the contract validates bitboard legality.
    applyManually(chess, uci);
  }
  return chess;
}

// Handle moves chess.js's public .move() refused. Castling-through-check
// doesn't appear in pseudo-legal output (chess.js filters at generation), so
// king-two-files gets a hand-rolled rook hop + FEN aux rewrite.
function applyManually(chess: Chess, uci: string) {
  const from = uci.slice(0, 2);
  const to = uci.slice(2, 4);
  const promotion = uci[4];

  const piece = chess.get(from as any);
  if (!piece) return;

  if (piece.type === 'k' && Math.abs(from.charCodeAt(0) - to.charCodeAt(0)) === 2) {
    return applyCastleManually(chess, piece, from, to);
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const internal = (chess as any)._moves({ legal: false }).find((m: any) => {
    const p = new Move(chess, m);
    return p.from === from && p.to === to && (p.promotion || undefined) === promotion;
  });
  if (internal) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (chess as any)._makeMove(internal);
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function applyCastleManually(chess: Chess, king: any, from: string, to: string) {
  const rank = king.color === 'w' ? '1' : '8';
  const corner = to[0] === 'g' ? `h${rank}` : `a${rank}`;
  const dest = to[0] === 'g' ? `f${rank}` : `d${rank}`;

  const [, prevTurn, prevCastling, , prevHalfmove, prevFullmove] = chess.fen().split(' ');

  chess.remove(from as any);
  chess.put(king, to as any);

  const rook = chess.get(corner as any);
  if (rook && rook.type === 'r' && rook.color === king.color) {
    chess.remove(corner as any);
    chess.put(rook, dest as any);
  }

  const newTurn = prevTurn === 'w' ? 'b' : 'w';
  let newCastling =
    king.color === 'w'
      ? prevCastling.replace(/[KQ]/g, '')
      : prevCastling.replace(/[kq]/g, '');
  if (newCastling === '') newCastling = '-';
  const newHalfmove = parseInt(prevHalfmove, 10) + 1;
  const newFullmove = king.color === 'b' ? parseInt(prevFullmove, 10) + 1 : parseInt(prevFullmove, 10);

  const [placement] = chess.fen().split(' ');
  chess.load(`${placement} ${newTurn} ${newCastling} - ${newHalfmove} ${newFullmove}`);
}

export function getFEN(moves: string[]): string {
  return replayMoves(moves).fen();
}

export function renderBoard(moves: string[]): string {
  return replayMoves(moves).ascii();
}

export interface LegalMove {
  from: string;
  to: string;
  promotion?: string;
  san: string;
  uci: string;
}

// Legal moves at the current position. Uses chess.js's standard legal-move
// generation (includes check filtering, excludes castle-through-check). The
// bot plays legally — pseudo-legal mode in the frontend is for accepting an
// opponent's already-broadcast move, not for choosing one.
export function legalMoves(moves: string[]): LegalMove[] {
  const chess = replayMoves(moves);
  return chess.moves({ verbose: true }).map((m) => ({
    from: m.from,
    to: m.to,
    promotion: m.promotion,
    san: m.san,
    uci: m.from + m.to + (m.promotion ?? ''),
  }));
}

// Mirror of contracts/src/lib/UCI.sol — accepts 4 or 5 chars; file a–h, rank
// 1–8; promotion piece q/r/b/n.
export function validateUCI(uci: string): { valid: boolean; reason?: string } {
  if (uci.length !== 4 && uci.length !== 5) {
    return { valid: false, reason: 'length must be 4 or 5' };
  }
  const file = (c: string) => c >= 'a' && c <= 'h';
  const rank = (c: string) => c >= '1' && c <= '8';
  if (!file(uci[0])) return { valid: false, reason: `bad from-file: ${uci[0]}` };
  if (!rank(uci[1])) return { valid: false, reason: `bad from-rank: ${uci[1]}` };
  if (!file(uci[2])) return { valid: false, reason: `bad to-file: ${uci[2]}` };
  if (!rank(uci[3])) return { valid: false, reason: `bad to-rank: ${uci[3]}` };
  if (uci.length === 5 && !'qrbn'.includes(uci[4])) {
    return { valid: false, reason: `bad promotion: ${uci[4]} (must be q/r/b/n)` };
  }
  return { valid: true };
}
