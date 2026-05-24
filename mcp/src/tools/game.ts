import { z } from 'zod';
import type { Address } from 'viem';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { lobby } from '../contracts/lobby.js';
import { chessEngineAbi, engineFor } from '../contracts/chessEngine.js';
import { signingFields, writeAs } from '../chain.js';
import { getFEN, legalMoves, renderBoard, validateUCI } from '../chess.js';
import { textResult, tool } from '../util.js';

const gameIdSchema = z.union([z.number().int().nonnegative(), z.string().regex(/^\d+$/)])
  .transform((v) => BigInt(v));

const GAME_STATE = ['Pending', 'Declined', 'Started', 'Draw', 'Finished', 'Review', 'Migrated'] as const;
const GAME_OUTCOME = ['Undecided', 'WhiteWon', 'BlackWon', 'Draw'] as const;

interface RawGameData {
  exists: boolean;
  state: number;
  outcome: number;
  whitePlayer: Address;
  blackPlayer: Address;
  currentMove: Address;
  timePerMove: bigint;
  timeOfLastMove: bigint;
  wagerAmount: bigint;
  wagerToken: Address;
}

export function registerGameTools(server: McpServer) {
  tool(server,
    'get_game',
    {
      title: 'Full game data',
      description:
        'Returns the GameData struct for a game: players, current mover, state, outcome, wager, timing. Enum fields are decoded to strings.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const g = (await engine.read.game([gameId])) as RawGameData;
      return textResult({
        gameId,
        engine: engine.address,
        exists: g.exists,
        state: GAME_STATE[g.state] ?? `Unknown(${g.state})`,
        outcome: GAME_OUTCOME[g.outcome] ?? `Unknown(${g.outcome})`,
        whitePlayer: g.whitePlayer,
        blackPlayer: g.blackPlayer,
        currentMove: g.currentMove,
        timePerMove: g.timePerMove,
        timeOfLastMove: g.timeOfLastMove,
        wagerAmount: g.wagerAmount,
        wagerToken: g.wagerToken,
      });
    },
  );

  tool(server,
    'get_moves',
    {
      title: 'Move log',
      description: 'The full UCI move log for a game in order played.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const moves = (await engine.read.moves([gameId])) as string[];
      return textResult({ gameId, moves });
    },
  );

  tool(server,
    'get_fen',
    {
      title: 'FEN at current position',
      description:
        'Replays the on-chain move log through chess.js and returns the resulting FEN. Pseudo-legal moves (king-in-check, castle-through-check) are applied via fallback to mirror frontend behavior.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const moves = (await engine.read.moves([gameId])) as string[];
      return textResult({ gameId, fen: getFEN(moves) });
    },
  );

  tool(server,
    'render_board',
    {
      title: 'ASCII board',
      description: 'Renders the current position as an 8x8 ASCII board (chess.js .ascii()).',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const moves = (await engine.read.moves([gameId])) as string[];
      return { content: [{ type: 'text' as const, text: renderBoard(moves) }] };
    },
  );

  tool(server,
    'time_remaining',
    {
      title: 'Seconds until move-timer expires',
      description:
        'Seconds left for the player whose turn it is. Returns 0 if expired. Returns null if no move has been played yet (timer not started).',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const g = (await engine.read.game([gameId])) as RawGameData;
      if (g.timeOfLastMove === 0n) {
        return textResult({ gameId, currentMove: g.currentMove, secondsRemaining: null });
      }
      const now = BigInt(Math.floor(Date.now() / 1000));
      const expiry = g.timeOfLastMove + g.timePerMove;
      const remaining = expiry > now ? expiry - now : 0n;
      return textResult({
        gameId,
        currentMove: g.currentMove,
        secondsRemaining: Number(remaining),
        expiresAt: Number(expiry),
      });
    },
  );

  tool(server,
    'game_engine_addr',
    {
      title: 'Per-game engine address',
      description:
        'Returns the ChessEngine contract address bound to this game. Older games stay pinned to their original engine after upgrades.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const address = (await lobby.read.chessEngine([gameId])) as Address;
      return textResult({ gameId, engine: address });
    },
  );

  tool(server,
    'legal_moves',
    {
      title: 'Legal moves at current position',
      description:
        'Replays the on-chain move log and returns the list of chess-legal moves available to the side to move. Each entry includes UCI, SAN, from/to squares, and promotion piece if any.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const engine = await engineFor(gameId);
      const moves = (await engine.read.moves([gameId])) as string[];
      return textResult({ gameId, legalMoves: legalMoves(moves) });
    },
  );

  tool(server,
    'validate_uci',
    {
      title: 'Validate UCI notation',
      description:
        'Checks a UCI move string against the syntax accepted by contracts/src/lib/UCI.sol: length 4 or 5, files a–h, ranks 1–8, promotion piece q/r/b/n. Does not check legality at any position.',
      inputSchema: { uci: z.string() },
    },
    async ({ uci }) => {
      return textResult({ uci, ...validateUCI(uci) });
    },
  );

  tool(server,
    'move',
    {
      title: 'Play a move',
      description:
        'Submit a UCI move to the per-game engine. Use validate_uci/legal_moves first to avoid wasted gas on rejected moves.',
      inputSchema: {
        gameId: gameIdSchema,
        uci: z.string().describe('UCI notation, e.g. "e2e4" or "a7a8q"'),
        ...signingFields,
      },
    },
    async ({ gameId, uci, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'move',
          args: [gameId, uci],
        },
      );
    },
  );

  tool(server,
    'resign',
    {
      title: 'Resign a game',
      description: 'Resign the game. Opponent wins; wager is paid out.',
      inputSchema: { gameId: gameIdSchema, ...signingFields },
    },
    async ({ gameId, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'resign',
          args: [gameId],
        },
      );
    },
  );

  tool(server,
    'offer_draw',
    {
      title: 'Offer a draw',
      description:
        'Offer a draw. The game state transitions to Draw and currentMove flips to the opponent, who must call respond_draw.',
      inputSchema: { gameId: gameIdSchema, ...signingFields },
    },
    async ({ gameId, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'offerDraw',
          args: [gameId],
        },
      );
    },
  );

  tool(server,
    'respond_draw',
    {
      title: 'Accept or decline a draw offer',
      description:
        'Respond to a standing draw offer. accept=true finishes the game as a draw; accept=false returns it to Started.',
      inputSchema: {
        gameId: gameIdSchema,
        accept: z.boolean(),
        ...signingFields,
      },
    },
    async ({ gameId, accept, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'respondDraw',
          args: [gameId, accept],
        },
      );
    },
  );

  tool(server,
    'claim_victory',
    {
      title: 'Claim victory on timeout',
      description:
        'Claim a win because the opponent’s move timer expired. Reverts (TimerActive) if the timer is still running.',
      inputSchema: { gameId: gameIdSchema, ...signingFields },
    },
    async ({ gameId, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'claimVictory',
          args: [gameId],
        },
      );
    },
  );

  tool(server,
    'raise_dispute',
    {
      title: 'Send the game to arbiter review',
      description:
        'Flag the game for arbiter review. State transitions to Review; an arbiter must call resolveDispute (not exposed here) to settle.',
      inputSchema: { gameId: gameIdSchema, ...signingFields },
    },
    async ({ gameId, from, signature, unsignedTx }) => {
      const engine = await engineFor(gameId);
      return writeAs(
        { from, signature, unsignedTx },
        {
          to: engine.address,
          abi: chessEngineAbi,
          functionName: 'disputeGame',
          args: [gameId],
        },
      );
    },
  );
}
