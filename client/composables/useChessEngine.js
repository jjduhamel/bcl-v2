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

  function tryMove(uci) {
    console.log('Try move', uci);
    const move = chess.move(uci, { sloppy: true });
    if (!move) {
      illegalMoves.value = [ ...illegalMoves.value, moves.value.length ];
      console.warn(`Illegal move: ${uci} [${chess.turn()}]`);
    } else if (move.flags.includes('e')) {
      // En passant: chess.js applies it but the contract rejects (per CLAUDE.md)
      chess.undo();
      illegalMoves.value = [ ...illegalMoves.value, moves.value.length ];
      console.warn(`En passant not supported: ${uci}`);
    }
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
