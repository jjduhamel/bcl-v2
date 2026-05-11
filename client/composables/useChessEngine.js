import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';
import { constants } from 'ethers';
import { fetchBlockNumber } from '@wagmi/core';

export default async function(gameId) {
  const { $amplitude } = useNuxtApp();

  const GameState = {
    Pending: 0,
    Declined: 1,
    Started: 2,
    Draw: 3,
    Finished: 4,
    Review: 5,
    Migrated: 6
  };

  const GameOutcome = {
    Undecided: 0,
    WhiteWon: 1,
    BlackWon: 2,
    Draw: 3
  };

  /*
   * Browser chess engine
   */
  const chess = new Chess();

  const fen = ref(chess.fen());

  // Castle destinations chess.js filters at generation when the king or path
  // is attacked (chess.ts:1045,1051). Contract validates the rest, so we just
  // check rights + empty path + rook at corner.
  const castleMoves = computed(() => {
    fen.value;
    const [, turn, castling] = chess.fen().split(' ');
    if (castling === '-') return [];
    const rank = turn === 'w' ? '1' : '8';
    if (chess.get('e' + rank)?.type !== 'k') return [];
    const dests = [];
    const kFlag = turn === 'w' ? 'K' : 'k';
    const qFlag = turn === 'w' ? 'Q' : 'q';
    if (castling.includes(kFlag)
        && !chess.get('f' + rank) && !chess.get('g' + rank)
        && chess.get('h' + rank)?.type === 'r') dests.push('g' + rank);
    if (castling.includes(qFlag)
        && !chess.get('b' + rank) && !chess.get('c' + rank) && !chess.get('d' + rank)
        && chess.get('a' + rank)?.type === 'r') dests.push('c' + rank);
    return dests;
  });

  const legalMoves = computed(() => {
    fen.value;            // Make reactive to FEN updates
    const out = new Map();
    _.forEach(SQUARES, sq => {
      // Pseudo-legal so the UI permits moves that leave the king in check.
      const ms = chess._moves({ legal: false, square: sq });
      if (ms.length > 0) out.set(sq, _.map(ms, m => chess._makePretty(m).to));
    });
    // Inject castle destinations chess.js filters at generation time.
    if (castleMoves.value.length > 0) {
      const kingSq = 'e' + (chess.turn() === 'w' ? '1' : '8');
      const existing = out.get(kingSq) || [];
      out.set(kingSq, [...new Set([...existing, ...castleMoves.value])]);
    }
    return out;
  });

  if (!gameId) {
    return { chess, fen, legalMoves, GameState, GameOutcome };
  }

  const { wallet, refreshBalance } = await useWallet();

  const {
    lobby,
    lobbyContract,
    chessEngine,
    initGameData,
    fetchGameData
  } = await useLobby();

  const { playAudioClip } = useAudioUtils();

  if (!lobby.has(gameId)) await initGameData(gameId);

  const gameContract = chessEngine(gameId);
  const { PlayerMoved, GameOver } = gameContract.filters;
  const moves = ref([]);
  const illegalMoves = ref([]);

  // Apply a castle (the king-jumps-2-files case) by hand. We need this only
  // because chess.js filters castle-through-check at pseudo-legal generation
  // (chess.ts:1045 calls _attacked on the path squares), and the contract's
  // _vKg has a TODO leaving castle-through-check legal on-chain — so the
  // opponent can produce one we still have to render.
  function applyCastleManually(king, from, to) {
    // The rook hops to the square the king passes over.
    //   Kingside (king e->g): rook h -> f
    //   Queenside (king e->c): rook a -> d
    const rank = king.color === 'w' ? '1' : '8';
    const corner = to[0] === 'g' ? 'h' + rank : 'a' + rank;
    const dest   = to[0] === 'g' ? 'f' + rank : 'd' + rank;

    // Snapshot the pre-move aux fields. chess.put / chess.remove only touch
    // the placement field; turn / castling / counters stay frozen at the
    // pre-move values until we rewrite them via chess.load below.
    const [, prevTurn, prevCastling, , prevHalfmove, prevFullmove] = chess.fen().split(' ');

    // Move the king. chess.put doesn't validate, so this works even when
    // chess.js's move() would have refused (e.g. castling out of check).
    chess.remove(from);
    chess.put(king, to);

    // Hop the rook — but only if a same-color rook is actually at the corner.
    // Defends against pathological positions or a "king moved 2 files but
    // wasn't really castling" UCI that the contract will end up rejecting.
    const rook = chess.get(corner);
    if (rook && rook.type === 'r' && rook.color === king.color) {
      chess.remove(corner);
      chess.put(rook, dest);
    }

    // Side to move flips after every ply.
    const newTurn = prevTurn === 'w' ? 'b' : 'w';

    // King moved => this color forfeits both castling rights.
    let newCastling = king.color === 'w'
      ? prevCastling.replace(/[KQ]/g, '')
      : prevCastling.replace(/[kq]/g, '');
    if (newCastling === '') newCastling = '-';

    // Halfmove clock increments (no pawn move, no capture in a castle).
    // Fullmove number bumps after Black moves.
    const newHalfmove = parseInt(prevHalfmove) + 1;
    const newFullmove = king.color === 'b' ? parseInt(prevFullmove) + 1 : parseInt(prevFullmove);

    // Splice the new aux fields back onto the (already updated) placement.
    // EP target is always cleared after a castle.
    const [placement] = chess.fen().split(' ');
    chess.load(`${placement} ${newTurn} ${newCastling} - ${newHalfmove} ${newFullmove}`);
  }

  // Update chess.js state to the post-move position WITHOUT chess-rule validation.
  //
  // The contract's bitboard validates piece movement but not chess rules like
  // "you may not leave your own king in check" (per CLAUDE.md). Those moves
  // are rejected by chess.js's public move() but accepted by the contract, so
  // when we receive (or are about to send) such a move we still need the local
  // board to advance.
  //
  // Approach: ask chess.js for pseudo-legal moves — i.e. _moves({legal:false}),
  // which includes moves that leave the king in check (chess.ts:1067-1071) —
  // find the one matching our UCI, and feed it to chess.js's internal _makeMove.
  // _makeMove reuses chess.js's own bookkeeping for capture, promotion, castling
  // rights, halfmove/fullmove counters, and EP target — so we don't have to
  // reimplement any of that.
  //
  // The exception is castling: chess.js filters castle moves at *generation*
  // time when the path is attacked, so castle-through-check never appears in
  // pseudo-legal output. Those fall through to applyCastleManually.
  function applyManually(uci) {
    // Decompose the UCI string. uci[4], when present, is the promotion piece.
    const from = uci.slice(0, 2);
    const to = uci.slice(2, 4);
    const promotion = uci[4] || undefined;

    // Bail if the source square is empty — the contract will reject this too.
    const piece = chess.get(from);
    if (!piece) return;

    // King jumps 2 files => castling. Hand off to the manual castle path.
    if (piece.type === 'k' && Math.abs(from.charCodeAt(0) - to.charCodeAt(0)) === 2) {
      return applyCastleManually(piece, from, to);
    }

    // Find the pseudo-legal move that matches our UCI. _makePretty converts
    // chess.js's internal move object (0x88 indices) into algebraic strings
    // we can compare against. If no match, the move was bitboard-illegal too;
    // we leave the board untouched and let submitMove's tx revert handle it.
    const match = chess._moves({ legal: false }).find(m => {
      const p = chess._makePretty(m);
      return p.from === from && p.to === to && (p.promotion || undefined) === promotion;
    });
    if (match) chess._makeMove(match);
  }

  function tryMove(uci) {
    console.log('Try move', uci);
    const move = chess.move(uci, { sloppy: true });
    if (!move) {
      // chess.js refused the move. Two sub-cases:
      //   (a) Move is bitboard-legal but chess-illegal (e.g. leaves king in
      //       check, castles through check). Contract will accept it.
      //   (b) Move is bitboard-illegal too. Contract will reject; submitMove's
      //       FEN-snapshot rollback restores the board.
      // In both cases we flag the move and try to apply it locally — for (a)
      // applyManually advances the board; for (b) it's a no-op (no matching
      // pseudo-legal move) and we just leave the board as-is.
      illegalMoves.value = [ ...illegalMoves.value, moves.value.length ];
      console.warn(`Illegal move: ${uci} [${chess.turn()}]`);
      applyManually(uci);
      fen.value = chess.fen();
      return { uci, illegal: true };
    } else if (move.flags.includes('e')) {
      // En passant: chess.js happily applied it, but the contract rejects EP
      // outright (per CLAUDE.md). Undo on chess.js side and mark rejected so
      // the caller can show the red flag and refuse to submit.
      chess.undo();
      illegalMoves.value = [ ...illegalMoves.value, moves.value.length ];
      console.warn(`En passant not supported: ${uci}`);
      fen.value = chess.fen();
      return { ...move, uci, rejected: true };
    }
    // Ordinary legal move — chess.js already updated the board.
    fen.value = chess.fen();
    return { ...move, uci };
  }

  async function fetchMoves() {
    console.log('Refresh moves for', gameId);
    moves.value = [];
    const cur = await gameContract.moves(gameId);
    console.log('Fetched', cur.length, 'moves');
    _.forEach(cur, uci => {
      moves.value = [ ...moves.value, tryMove(uci) ];
    });
  }


  const submitMove = uci => new Promise(async (resolve, reject) => {
    // Snapshot the pre-submit FEN so we can roll the board back if the tx
    // reverts. Since applyManually can advance the board for chess-illegal
    // moves, chess.history() / chess.undo() can't reach our previous state —
    // we have to restore via chess.load.
    const fenSnapshot = fen.value;
    try {
      console.log('Submit move', uci);
      $amplitude.track('SendMove', { gameId, uci });
      await gameContract.move(gameId, uci);
      playAudioClip('other/swell1');
      const eventFilter = PlayerMoved(gameId, wallet.address);
      gameContract.once(eventFilter, async (id, player, uci)  => {
        console.log('Move confirmed', uci);
        resolve(id, player, uci);
        await fetchGameData(gameId);
      });
    } catch(err) {
      console.error(err);
      // Tx reverted — restore the board to its pre-submit state.
      chess.load(fenSnapshot);
      fen.value = fenSnapshot;
      reject(err);
    }
  });

  const resign = () => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('ResignGame', { gameId });
      await gameContract.resign(gameId);
      console.log('Resigned game', gameId);
      playAudioClip('other/swell3');
      gameContract.once(GameOver(gameId), (id, winner, loser)  => {
        if (loser !== wallet.address) {
          return reject(new Error(`Expected loser ${wallet.address}, got ${loser}`));
        }
        console.log('Resignation confirmed');
        $amplitude.track('ResignedGame', { gameId });
        resolve(id, winner, loser);
      });
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  const claimVictory = () => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('ClaimVictory', { gameId });
      await gameContract.claimVictory(gameId);
      console.log('Claimed victory in game', gameId);
      playAudioClip('other/swell2');
      gameContract.once(GameOver(gameId), (id, winner, loser)  => {
        if (winner !== wallet.address) {
          return reject(new Error(`Expected winner ${wallet.address}, got ${winner}`));
        }
        console.log('Victory confirmed');
        $amplitude.track('VictoryConfirmed', { gameId, winner, loser });
        resolve(id, winner, loser);
      });
    } catch(err) {
      reject(err);
    }
  });

  async function offerStalemate() {
    // TODO
  }

  const withdrawWinnings = () => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('WithdrawWinnings', { gameId });
      const tx = await gameContract.withdraw(constants.AddressZero);
      await tx.wait();
      console.log('Withdrew winnings for game', gameId);
      playAudioClip('nes/Victory');
      await refreshBalance();
      resolve();
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  const disputeGame = () => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('DisputeGame', { gameId });
      await gameContract.disputeGame(gameId);
      console.log('Disputed game', gameId);
      playAudioClip('nes/GenericNotify');
      const { GameDisputed } = lobbyContract.filters;
      gameContract.once(GameDisputed(gameId), (id, outcome, winner)  => {
        console.log('Dispute received');
        $amplitude.track('GameDisputed', { gameId });
        resolve(id, outcome, winner);
      });
    } catch(err) {
      reject(err);
    }
  });

  /*
   * Reactive Properties
   */
  const gameData = computed(() => lobby.gameData(gameId));

  const opponent = computed(() => lobby.gameData(gameId).opponent);

  const isWhitePlayer = computed(() => {
    return lobby.gameData(gameId).whitePlayer == wallet.address;
  });

  const isBlackPlayer = computed(() => {
    return lobby.gameData(gameId).blackPlayer == wallet.address;
  });

  const isPlayer = computed(() => isWhitePlayer || isBlackPlayer);

  const playerColor = computed(() => {
    if (!isPlayer) throw Error('Not a player');
    return isWhitePlayer.value ? 'w' : 'b';
  });

  const opponentColor = computed(() => {
    if (!isPlayer) throw Error('Not a player');
    return isWhitePlayer.value ? 'b' : 'w';
  });


  const isCurrentMove = computed(() =>  lobby.isCurrentMove(gameId));
  const isOpponentsMove = computed(() => !isCurrentMove);

  // Turn follows the current chess engine, as opposed to the contract state
  const isPlayersTurn = computed(() => {
    fen.value;
    return chess.turn() == playerColor.value;
  });

  const isOpponentsTurn = computed(() => {
    fen.value;
    return chess.turn() == opponentColor.value;
  });

  const timeOfLastMove = computed(() => lobby.gameData(gameId).timeOfLastMove);

  const outcome = computed(() => lobby.gameData(gameId).outcome);
  const wagerAmount = computed(() => lobby.gameData(gameId).wagerAmount);
  const gameOver = computed(() => lobby.gameData(gameId).state == GameState.Finished);
  const isDisputed = computed(() => lobby.gameData(gameId).state == GameState.Review);
  const isStalemate = computed(() => outcome.value == GameOutcome.Draw);

  const inCheck = computed(() => {
    fen.value;
    return (chess.turn() == playerColor.value) && chess.isCheck();
  });

  const opponentInCheck = computed(() => {
    fen.value;
    return (chess.turn() == opponentColor.value) && chess.isCheck();
  });

  const inCheckmate = computed(() => {
    fen.value;
    return (chess.turn() == playerColor.value) && chess.isCheckmate();
  });

  const opponentInCheckmate = computed(() => {
    fen.value;
    return (chess.turn() == opponentColor.value) && chess.isCheckmate();
  });

  const inStalemate = computed(() => {
    fen.value;
    return chess.isStalemate();
  });

  const checkmatePending = computed(() => {
    fen.value;
    return !gameOver.value && inCheckmate.value;
  });

  const opponentCheckmatePending = computed(() => {
    return !gameOver.value && opponentInCheckmate.value;
  });

  const isWinner = computed(() => {
    return isPlayer.value && gameOver.value &&
          ((isWhitePlayer.value && outcome.value == GameOutcome.WhiteWon) ||
           (isBlackPlayer.value && outcome.value == GameOutcome.BlackWon));
  });

  const isLoser = computed(() => {
    return isPlayer.value && gameOver.value && !isStalemate.value && !isWinner.value;
  });

  /*
   * Timer Stuff
   */
  const moveTimer = ref(0);
  let _tMoveTimer = null;

  function startMoveTimer() {
    if (!_tMoveTimer) {
      console.log('Start move timer');
      _tMoveTimer = setInterval(() => moveTimer.value++, 1000);
    }
  }

  function stopMoveTimer() {
    console.log('Stop move timer');
    clearInterval(_tMoveTimer);
  }

  const timeOfExpiry = computed(() => {
    const { timePerMove } = gameData.value;
    return timeOfLastMove.value + timePerMove;
  });

  const timeUntilExpiry = computed(() => {
    moveTimer.value;
    const remaining = Math.floor(timeOfExpiry.value - Date.now()/1000);
    return Math.max(remaining, 0);
  });

  const timerExpired = computed(() => {
    return timeUntilExpiry.value == 0;
  });

  const playerTimeExpired = computed(() => {
    return isCurrentMove.value && timerExpired.value;
  });

  const opponentTimeExpired = computed(() => {
    return !isCurrentMove.value && timerExpired.value;
  });

  /*
   * Event Listeners
   */

  async function registerListeners() {
    console.log('Register listeners for game', gameId);
    let lastEvent = await fetchBlockNumber();
    gameContract.on(PlayerMoved(gameId), async (id, player, uci, ev) => {
      console.log('Received move from', player);
      $amplitude.track('MoveConfirmed', { gameId, player, uci });
      // Toss duplicate events
      if (ev.blockNumber <= lastEvent) return;
      lastEvent = ev.blockNumber;

      // If these come from the current player, then we already tried
      // the move and it succeeded.  Trying again would throw an error.
      // In the case of spectators, both players moves get processed.
      let move;
      if (player != wallet.address) {
        console.log('Received move', uci);
        move = tryMove(uci);
      } else {
        const last = _.last(chess.history({ verbose: true }));
        move = last ? { ...last, uci } : { uci };
      }
      moves.value = [ ...moves.value, move ];
      await fetchGameData(gameId);
      playAudioClip('other/Blaster');
    });

    gameContract.on(GameOver(gameId), async (id, winner, loser) => {
      console.log('Game over', id);
      await Promise.all([
        refreshBalance(),
        fetchGameData(gameId)
      ]);
      $amplitude.track('GameOver', { gameId, winner, loser });
      if (isWinner.value) playAudioClip('nes/Victory');
      else if (isLoser.value) playAudioClip('nes/Defeat');
      else playAudioClip('nes/Draw');
    });
  }

  async function destroyListeners() {
    console.log('Destroy game listeners for', gameId);
    gameContract.off(PlayerMoved(gameId));
    gameContract.off(GameOver(gameId));
  }

  return {
    chess,
    fen,
    legalMoves,
    moves,
    illegalMoves,
    gameContract,
    fetchMoves,
    gameData,
    GameState,
    GameOutcome,
    opponent,
    outcome,
    wagerAmount,
    //playerColor,
    //opponentColor,
    isPlayer,
    isWhitePlayer,
    isBlackPlayer,
    isCurrentMove,
    isOpponentsMove,
    isPlayersTurn,
    isOpponentsTurn,
    inCheck,
    opponentInCheck,
    inCheckmate,
    opponentInCheckmate,
    checkmatePending,
    opponentCheckmatePending,
    inStalemate,
    gameOver,
    isDisputed,
    isStalemate,
    isWinner,
    isLoser,
    timeOfExpiry,
    timeUntilExpiry,
    timerExpired,
    playerTimeExpired,
    opponentTimeExpired,
    tryMove,
    submitMove,
    resign,
    claimVictory,
    offerStalemate,
    withdrawWinnings,
    disputeGame,
    startMoveTimer,
    stopMoveTimer,
    registerListeners,
    destroyListeners,
  };
}
