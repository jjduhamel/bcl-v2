import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';

export default async function(gameId) {
  const { $amplitude } = useNuxtApp();

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

  /*
   * Browser chess engine
   */
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

  if (!gameId) {
    return { chess, fen, legalMoves, GameState, GameOutcome };
  }

  const {
    wallet,
    provider,
    refreshBalance
  } = await useWallet();

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
  const { MoveSAN, GameOver } = gameContract.filters;
  const moves = ref([]);
  const illegalMoves = ref([]);

  function tryMoveSAN(san) {
    console.log('Try move', san);
    const move = chess.move(san, { sloppy: true });
    if (!move) {
      const m = moves.value.length;
      illegalMoves.value = [ ...illegalMoves.value, m ];
      console.warn(`Illegal move: ${san} [${chess.turn()}]`);
    } else {
      san = move.san;
    }
    moves.value = [ ...moves.value, san ];
    fen.value = chess.fen();
    return san;
  }

  // TODO Place illegal moves on board
  function tryMoveFromTo(from, to) {
    return tryMoveSAN(`${from}${to}`);
  }

  async function fetchMoves() {
    console.log('Refresh moves for', gameId);
    moves.value = [];
    const cur = await gameContract.moves(gameId);
    console.log('Fetched', cur.length, 'moves');
    _.forEach(cur, tryMoveSAN);
  }


  const submitMove = san => new Promise(async (resolve, reject) => {
    try {
      console.log('Submit move', san);
      $amplitude.track('SendMove', { gameId, san });
      await gameContract.move(gameId, san);
      playAudioClip('other/swell1');
      const eventFilter = MoveSAN(gameId, wallet.address);
      gameContract.once(eventFilter, async (id, player, san)  => {
        console.log('Move confirmed', san);
        resolve(id, player, san);
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
      gameContract.once(GameOver(gameId), (id, outcome, winner)  => {
        console.log('Resignation confirmed');
        $amplitude.track('ResignedGame', { gameId });
        resolve(id, outcome, winner);
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
      gameContract.once(GameOver(gameId), (id, outcome, winner)  => {
        console.log('Victory confirmed');
        $amplitude.track('VictoryConfirmed', { gameId, outcome, winner });
        resolve(id, outcome, winner);
      });
    } catch(err) {
      reject(err);
    }
  });

  async function offerStalemate() {
    // TODO
  }

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
      $amplitude.track('MoveConfirmed', { gameId, player, san });
      // Toss duplicate events
      if (ev.blockNumber <= lastEvent) return;
      lastEvent = ev.blockNumber;
      // If these come from the current player, then we already tried
      // the move and it succeeded.  Trying again would throw an error.
      // In the case of spectators, both players moves get processed.
      if (player != wallet.address) {
        console.log('Received move', san);
        const move = tryMoveSAN(san);
      }
      moves.value = [ ...moves.value, san ];
      playAudioClip('other/Blaster');
      await fetchGameData(gameId);
    });

    gameContract.on(GameOver(gameId), async (id, outcome, winner) => {
      console.log('Game over', id);
      await Promise.all([
        refreshBalance(),
        fetchGameData(gameId)
      ]);
      $amplitude.track('GameOver', { gameId, outcome, winner });
      if (isWinner.value) playAudioClip('nes/Victory');
      else if (isLoser.value) playAudioClip('nes/Defeat');
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
    moves,
    illegalMoves,
    gameContract,
    fetchMoves,
    gameData,
    GameState,
    GameOutcome,
    opponent,
    outcome,
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
    isStalemate,
    isWinner,
    isLoser,
    timeOfExpiry,
    timeUntilExpiry,
    timerExpired,
    playerTimeExpired,
    opponentTimeExpired,
    tryMoveSAN,
    tryMoveFromTo,
    submitMove,
    resign,
    claimVictory,
    offerStalemate,
    disputeGame,
    startMoveTimer,
    stopMoveTimer,
    registerListeners,
    destroyListeners,
  };
}
