import _ from 'lodash';
import { Chess } from 'chess.js';
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

  // Dev flag (NUXT_PUBLIC env). When true the UI lets the player pick
  // pseudo-legal moves (e.g. leaving their own king in check) and castle-
  // through-check. Off by default; opponents' chess-illegal moves are still
  // applied via tryMove regardless of this flag. Destructured once at setup
  // so downstream computeds capture a plain boolean (no reactivity thrash).
  const { allowPseudoLegalMoves } = useRuntimeConfig().public;

  // Castle destinations chess.js filters at generation when the king or path
  // is attacked (chess.ts:1045,1051). Contract validates the rest, so we just
  // check rights + empty path + rook at corner. Only surfaced when the dev
  // flag is on; otherwise chess.js's own (legal) castle generation is enough.
  const castleMoves = computed(() => {
    if (!allowPseudoLegalMoves) return [];
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
    // One pseudo-/legal generation pass for all squares, grouped by from.
    // When the dev flag is on, legal:false lets the player pick moves that
    // leave their own king in check.
    for (const m of chess._moves({ legal: !allowPseudoLegalMoves })) {
      const p = chess._makePretty(m);
      if (!out.has(p.from)) out.set(p.from, []);
      out.get(p.from).push(p.to);
    }
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
  const {
    PlayerMoved,
    GameOver,
    OfferedDraw,
    DeclinedDraw
  } = gameContract.filters;
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
    // Rollback on tx revert is the caller's responsibility — by the time we
    // get here the board has already advanced via chooseMove, so we don't have
    // the pre-choose FEN. The page's undoMove() restores from fenBeforeChoose.
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

  // Send a draw offer. Contract flips state -> Draw and currentMove -> opponent,
  // so after this resolves the receiver gets the OfferedDraw event (handled in
  // the broadcast listener) and our UI shows "waiting on opponent" via the
  // drawOfferSent computed below. Mirror of resign(): wait for the event keyed
  // on our address before resolving so callers can chain on it.
  const offerStalemate = () => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('OfferDraw', { gameId });
      await gameContract.offerDraw(gameId);
      console.log('Offered draw on game', gameId);
      playAudioClip('other/swell3');
      gameContract.once(OfferedDraw(gameId, wallet.address), async (id, sender, receiver) => {
        console.log('Draw offer confirmed');
        $amplitude.track('DrawOffered', { gameId, receiver });
        await fetchGameData(gameId);
        resolve(id, sender, receiver);
      });
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  // Respond to an incoming draw offer. On accept the contract calls
  // finishGame(Draw) which emits GameOver — we wait on that. On decline the
  // contract reverts state to Started and flips currentMove back to the
  // original sender, then emits DeclinedDraw.
  const respondDraw = accept => new Promise(async (resolve, reject) => {
    try {
      $amplitude.track('RespondDraw', { gameId, accept });
      await gameContract.respondDraw(gameId, accept);
      console.log(accept ? 'Accepted draw' : 'Declined draw', 'on game', gameId);
      if (accept) {
        // GameOver handler in registerListeners refetches data and plays the
        // draw audio clip; here we just resolve once it fires.
        gameContract.once(GameOver(gameId), (id, winner, loser) => {
          $amplitude.track('DrawAccepted', { gameId });
          resolve(id, winner, loser);
        });
      } else {
        playAudioClip('nes/Explosion');
        gameContract.once(DeclinedDraw(gameId, wallet.address), async (id, sender, receiver) => {
          $amplitude.track('DrawDeclined', { gameId });
          await fetchGameData(gameId);
          resolve(id, sender, receiver);
        });
      }
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

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

  // Draw-offer state. While a draw is pending the contract sets state == Draw
  // and currentMove == receiver (the player who must accept or decline). So
  // isCurrentMove distinguishes the two roles for us.
  const inDrawOffer = computed(() => lobby.gameData(gameId).state == GameState.Draw);
  const drawOfferReceived = computed(() => inDrawOffer.value && isCurrentMove.value);
  const drawOfferSent = computed(() => inDrawOffer.value && !isCurrentMove.value);

  const inCheck = computed(() => {
    fen.value;
    // After a king capture chess.js's _kings[them] still points at the
    // captured square, so isCheck() can report stale truth. Short-circuit
    // once the contract has confirmed game-over.
    if (gameOver.value) return false;
    return (chess.turn() == playerColor.value) && chess.isCheck();
  });

  const opponentInCheck = computed(() => {
    fen.value;
    if (gameOver.value) return false;
    return (chess.turn() == opponentColor.value) && chess.isCheck();
  });

  // Symmetric to opponentKingAttacked, for the loser's view: our king is
  // currently under attack from one of their pieces, regardless of turn.
  const playerKingAttacked = computed(() => {
    fen.value;
    if (gameOver.value) return false;
    return chess._attacked(opponentColor.value, chess._kings[playerColor.value]);
  });

  const inCheckmate = computed(() => {
    fen.value;
    if (gameOver.value) return false;
    if (chess.turn() == playerColor.value) {
      if (chess.isCheckmate()) return true;
    } else {
      // After we've made an illegal move that didn't escape check, the turn
      // flips to the opponent and chess.js no longer reports mate — but our
      // king is still under their attack with no way out.
      return playerKingAttacked.value;
    }
  });

  const opponentInCheckmate = computed(() => {
    fen.value;
    if (gameOver.value) return false;
    // Standard mate detection: chess.js sees it when the side to move (the
    // opponent) has no legal escape.
    if (chess.turn() == opponentColor.value) {
      if (chess.isCheckmate()) return true;
    } else {
      // Turn-independent check: their king is under attack from one of our
      // pieces. Survives the local turn-flip when the player chooses a non-
      // king-capture move; only false when *our* king is the exposed one.
      return opponentKingAttacked.value;
    }
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

  // Is the opponent's king currently attacked by one of our pieces? Uses
  // chess._attacked so it works regardless of whose turn it is — survives
  // the turn-flip when the player chooses a non-king-capture move locally.
  const opponentKingAttacked = computed(() => {
    fen.value;
    if (gameOver.value) return false;
    return chess._attacked(playerColor.value, chess._kings[opponentColor.value]);
  });

  // If we can capture the opponent's king on our turn, return the UCI for it.
  // Returns null when it's not our turn — gates the Claim Victory button.
  const kingCaptureUci = computed(() => {
    fen.value;
    if (gameOver.value || !isPlayersTurn.value || !opponentKingAttacked.value) return null;
    for (const m of chess._moves({ legal: false })) {
      const p = chess._makePretty(m);
      if (p.captured === 'k') return p.from + p.to + (p.promotion || '');
    }
    return null;
  });

  const canCaptureKing = computed(() => kingCaptureUci.value !== null);

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

    // Draw lifecycle. AcceptedDraw is always followed by GameOver, so we let
    // the GameOver handler above own the final state refresh + draw audio.
    // Here we only handle the two intermediate transitions (offer raised, offer
    // declined), and we skip the audio when we're the originator since the
    // action function (offerStalemate / respondDraw) already played a cue.
    gameContract.on(OfferedDraw(gameId), async (id, sender) => {
      console.log('Draw offered by', sender);
      await fetchGameData(gameId);
      if (sender !== wallet.address) playAudioClip('nes/GenericNotify');
    });

    gameContract.on(DeclinedDraw(gameId), async (id, sender) => {
      console.log('Draw declined by', sender);
      await fetchGameData(gameId);
      if (sender !== wallet.address) playAudioClip('nes/Explosion');
    });
  }

  async function destroyListeners() {
    console.log('Destroy game listeners for', gameId);
    gameContract.off(PlayerMoved(gameId));
    gameContract.off(GameOver(gameId));
    gameContract.off(OfferedDraw(gameId));
    gameContract.off(DeclinedDraw(gameId));
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
    kingCaptureUci,
    canCaptureKing,
    inStalemate,
    gameOver,
    isDisputed,
    isStalemate,
    inDrawOffer,
    drawOfferReceived,
    drawOfferSent,
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
    respondDraw,
    withdrawWinnings,
    disputeGame,
    startMoveTimer,
    stopMoveTimer,
    registerListeners,
    destroyListeners,
  };
}
