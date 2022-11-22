import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';

export default async function(gameId) {
  const engine = new Chess();

  const fen = ref(engine.fen());

  const legalMoves = computed(() => {
    fen.value;            // Make reactive to FEN updates
    const out = new Map();
    _.forEach(SQUARES, sq => {
      const ms = engine.moves({ square: sq, verbose: true });
      if (ms.length > 0) out.set(sq, _.map(ms, 'to'));
    });
    return out;
  });

  if (!gameId) {
    return { engine, fen, legalMoves };
  }

  console.log('Initialize game', gameId);
  const { wallet, provider } = await useWallet();
  const { lobby } = await useLobby();
  const gameContract = lobby.chessEngine(gameId);

  const moves = await gameContract.moves(gameId).then(ref);

  // TODO Place illegal moves
  function tryMove(san) {
    console.log('Try move', san);
    const move = engine.move(san);
    if (!move) throw Error('Illegal move: '+san);
    fen.value = engine.fen();
    return move.san;
  }

  console.log('Initialize', moves.value.length, 'moves');
  _.forEach(moves.value, tryMove);

  const didSendMove = ref(false);
  const submitMove = san => new Promise(async (resolve, reject) => {
    try {
      await gameContract.move(gameId, san);
      console.log('Submit move', san);
      didSendMove.value = true;
      const { MoveSAN } = gameContract.filters;
      const eventFilter = MoveSAN(gameId, wallet.address);
      gameContract.once(eventFilter, async (id, player, san)  => {
        console.log('Move confirmed', san);
        didSendMove.value = false;
        resolve(id, player, san);
      });
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  const didSendResign = ref(false);
  const resign = () => new Promise(async (resolve, reject) => {
    try {
      await gameContract.resign(gameId);
      console.log('Resigned game', gameId);
      didSendResign.value = true;
      const { GameOver } = gameContract.filters;
      const eventFilter = GameOver(gameId);
      gameContract.once(eventFilter, (id, winner, loser)  => {
        console.log('Resignation confirmed');
        didSendResign.value = false;
        resolve(id, winner, loser);
      });
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  const didClaimVictory = ref(false);
  const claimVictory = () => new Promise(async (resolve, reject) => {
    try {
      await gameContract.claimVictory(gameId);
      console.log('Claimed victory in game', gameId);
      didClaimVictory.value = true;
      const { GameOver } = gameContract.filters;
      const eventFilter = GameOver(gameId);
      gameContract.once(eventFilter, (id, winner, loser)  => {
        console.log('Claimed victory');
        didClaimVictory.value = false;
        resolve(id, winner, loser);
      });
    } catch(err) {
      console.error(err);
      reject(err);
    }
  });

  const didOfferStalemate = ref(false);
  async function offerStalemate() {
    // TODO
  }

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

  const timeOfLastMove = computed(() => lobby.gameData(gameId).timeOfLastMove);

  const inCheck = computed(() => {
    fen.value;
    return (engine.turn() == playerColor.value) && engine.isCheck();
  });

  const opponentInCheck = computed(() => {
    fen.value;
    return (engine.turn() == opponentColor.value) && engine.isCheck();
  });

  const inCheckmate = computed(() => {
    fen.value;
    return (engine.turn() == playerColor.value) && engine.isCheckmate();
  });

  const opponentInCheckmate = computed(() => {
    fen.value;
    return (engine.turn() == opponentColor.value) && engine.isCheckmate();
  });

  const inStalemate = computed(() => {
    fen.value;
    return engine.isStalemate();
  });

  const outcome = computed(() => lobby.gameData(gameId).outcome);
  const gameOver = computed(() => lobby.gameData(gameId).state == 4);
  const isStalemate = computed(() => outcome.value == 3);
  const isWinner = computed(() => {
    return isPlayer.value && gameOver.value &&
          ((isWhitePlayer.value && outcome.value == 1) ||
           (isBlackPlayer.value && outcome.value == 2));
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

  /*
   * Event Listeners
   */

  const { MoveSAN, GameOver } = gameContract.filters;
  const moveEvent = MoveSAN(gameId);
  const gameOverEvent = GameOver(gameId);

  async function registerListeners() {
    console.log('Listen for moves for game', gameId);
    let lastEvent = await provider.getBlockNumber();
    gameContract.on(moveEvent, async (id, player, san, ev) => {
      // Toss duplicate events
      if (ev.blockNumber <= lastEvent) return;
      lastEvent = ev.blockNumber;
      // If these come from the current player, then we already tried
      // the move and it succeeded.  Trying again would throw an error.
      // In the case of spectators, both players moves get processed.
      if (player != wallet.address) {
        console.log('Received move', san);
        const move = tryMove(san);
        // TODO Dispute illegal moves
      }
      // TODO is there a better way/place to do this?
      moves.value = [ ...moves.value, san ];
      await lobby.fetchMetadata(gameId);
    });

    gameContract.on(gameOverEvent, async (id, winner, loser) => {
      console.log('Game over', id);
      await lobby.fetchMetadata(gameId);
    });
  }

  async function destroyListeners() {
    console.log('Destroy Listeners');
    gameContract.off(moveEvent);
    gameContract.off(gameOverEvent);
  }

  return {
    engine,
    fen,
    legalMoves,
    moves,
    gameContract,
    gameData,
    opponent,
    //playerColor,
    //opponentColor,
    isPlayer,
    isWhitePlayer,
    isBlackPlayer,
    isCurrentMove,
    isOpponentsMove,
    inCheck,
    opponentInCheck,
    inCheckmate,
    opponentInCheckmate,
    inStalemate,
    outcome,
    gameOver,
    isStalemate,
    isWinner,
    isLoser,
    registerListeners,
    destroyListeners,
    startMoveTimer,
    stopMoveTimer,
    timeOfExpiry,
    timeUntilExpiry,
    timerExpired,
    tryMove,
    submitMove,
    didSendMove,
    resign,
    claimVictory,
    didSendResign,
    offerStalemate,
    didOfferStalemate
  };
}
