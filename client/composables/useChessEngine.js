import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';

export default async function(gameId) {
  const chess = new Chess();

  const fen = ref(chess.fen());

  const legalMoves = computed(() => {
    fen.value;            // Make reactive to FEN updates
    const out = new Map();
    _.forEach(SQUARES, sq => {
      const ms = chess.moves({ square: sq, verbose: true });
      if (ms.length > 0) out.set(sq, _.map(ms, 'to'));
    });
    return out;
  });

  const GameState = {
    Pending: 0,
    Started: 1,
    Draw: 2,
    Finished: 3,
    Review: 4,
    Migrated: 5
  };

  const GameOutcome = {
    Undecided: 0,
    Declined: 1,
    WhiteWon: 2,
    BlackWon: 3,
    Draw: 4
  };

  if (!gameId) {
    return { chess, fen, legalMoves, GameState, GameOutcome };
  }

  console.log('Initialize game', gameId);
  const { wallet, provider, refreshBalance } = await useWallet();
  const { lobby, chessEngine, initGameData } = await useLobby();
  const { playAudioClip } = useAudioUtils();

  if (!lobby.has(gameId)) await initGameData(gameId);

  const gameContract = chessEngine(gameId);
  const { MoveSAN, GameOver } = gameContract.filters;
  const moves = await gameContract.moves(gameId).then(ref);

  // TODO Place illegal moves
  function tryMove(san) {
    console.log('Try move', san);
    const move = chess.move(san);
    if (!move) throw Error('Illegal move: '+san);
    fen.value = chess.fen();
    return move.san;
  }

  console.log('Initialize', moves.value.length, 'moves');
  _.forEach(moves.value, tryMove);

  const didSendMove = ref(false);
  const submitMove = san => new Promise(async (resolve, reject) => {
    console.log('Submit move', san);
    try {
      await gameContract.move(gameId, san);
      didSendMove.value = true;
      playAudioClip('instrument/swells/swell1');
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
      playAudioClip('instrument/swells/swell3');
      gameContract.once(GameOver(gameId), (id, outcome, winner)  => {
        console.log('Resignation confirmed');
        didSendResign.value = false;
        resolve(id, outcome, winner);
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
      playAudioClip('instrument/swells/swell2');
      gameContract.once(GameOver(gameId), (id, outcome, winner)  => {
        console.log('Claimed victory');
        didClaimVictory.value = false;
        resolve(id, outcome, winner);
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

  const outcome = computed(() => lobby.gameData(gameId).outcome);
  const gameOver = computed(() => lobby.gameData(gameId).state == GameState.Finished);
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
    let lastEvent = await provider.getBlockNumber();
    gameContract.on(MoveSAN(gameId), async (id, player, san, ev) => {
      // Toss duplicate events
      if (ev.blockNumber <= lastEvent) return;
      lastEvent = ev.blockNumber;
      // If these come from the current player, then we already tried
      // the move and it succeeded.  Trying again would throw an error.
      // In the case of spectators, both players moves get processed.
      if (player != wallet.address) {
        console.log('Received move', san);
        const move = tryMove(san);
        playAudioClip('other/Blaster');
        // TODO Dispute illegal moves
      }
      // TODO is there a better way/place to do this?
      moves.value = [ ...moves.value, san ];
      await fetchGameData(gameId);
    });

    gameContract.on(GameOver(gameId), async (id, outcome, winner) => {
      console.log('Game over', id);
      await Promise.all([
        refreshBalance(),
        fetchGameData(gameId)
      ]);

      if (isWinner.value) playAudioClip('nes/Victory');
      else if (isLoser.value) playAudioClip('nes/Victory');
      else playAudioClip('nes/Draw');
    });
  }

  async function destroyListeners() {
    console.log('Destroy game listeners for', gameId);
    gameContract.off(MoveSAN(gameId));
    gameContract.off(GameOver(gameId));
  }

  return {
    chess,
    fen,
    legalMoves,
    GameState,
    GameOutcome,
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
    checkmatePending,
    opponentCheckmatePending,
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
    playerTimeExpired,
    opponentTimeExpired,
    tryMove,
    submitMove,
    didSendMove,
    resign,
    didSendResign,
    claimVictory,
    didClaimVictory,
    offerStalemate,
    didOfferStalemate
  };
}
