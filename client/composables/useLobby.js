import _ from 'lodash';
import { ethers, Contract, BigNumber as BN } from 'ethers';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useLobbyStore from '../store/lobby';

export default async function() {
  const lobby = useLobbyStore();
  const { wallet, provider, signer, refreshBalance } = await useWallet();
  const { playAudioClip } = useAudioUtils();

  const lobbyContract = new Contract(lobby.address
                                   , LobbyContract.abi
                                   , signer || provider);

  const {
    TouchRecord,
    NewChallenge,
    ChallengeDeclined,
    ChallengeAccepted,
    GameFinished
  } = lobbyContract.filters;

  if (wallet.connected && !lobby.initialized) {
    await initialize();
  }

  async function initialize() {
    console.log('Initialize player lobby', lobby.address);

    const [ challenges, games, history ] = await Promise.all([
      lobbyContract.challenges(),
      lobbyContract.games(),
      lobbyContract.history()
    ]);

    await Promise.all(_.map([
      ...challenges,
      ...games,
      ...history
    ], initGameData));

    lobby.pending = _.map(challenges, gameId => gameId.toNumber());
    console.log('Synced', challenges.length, 'challenges');
    lobby.current = _.map(games, gameId => gameId.toNumber());
    console.log('Synced', games.length, 'games');
    lobby.finished = _.map(history, gameId => gameId.toNumber());
    console.log('Synced', history.length, 'finished games');

    lobby.initialized = true;
  };

  async function initGameData(id) {
    const gameId = BN.from(id).toNumber();
    console.log('Initialize game data', gameId);
    await fetchChessEngine(gameId);
    await fetchGameData(gameId);
  }

  function chessEngine(gameId) {
    return new Contract(lobby.engineAddress(gameId)
                      , EngineContract.abi
                      , signer || provider);
  }

  async function fetchChessEngine(gameId) {
    const engineAddress = await lobbyContract.chessEngine(gameId);
    console.log('Engine for game', gameId, 'is', engineAddress);
    if (!engineAddress) throw Error('MissingRecord');
    lobby.contracts[gameId] = engineAddress;
    return chessEngine(gameId);
  }

  async function fetchGameData(gameId) {
    console.log('Fetch data for game', gameId);
    const [
      , state
      , outcome
      , whitePlayer
      , blackPlayer
      , currentMove
      , timePerMove
      , timeOfLastMove
      , wagerAmount
    ] = await chessEngine(gameId).game(gameId);

    lobby.metadata[gameId] = {
      id: BN.from(gameId).toNumber(),
      state,
      outcome,
      whitePlayer,
      blackPlayer,
      currentMove,
      ..._.mapValues({ timePerMove, timeOfLastMove },
                     bn => bn.toNumber()),
      ..._.mapValues({ wagerAmount },
                     bn => bn.toString())
    };
  }

  const didSendChallenge = ref(false);
  const sendChallenge = (opponent
                       , startAsWhite
                       , timePerMove
                       , wagerAmount
                       , wagerToken) => new Promise(async (resolve, reject) => {

    try {
      didSendChallenge.value = true;
      await lobbyContract.challenge(opponent
                                  , startAsWhite
                                  , timePerMove
                                  , wagerAmount
                                , { value: wagerAmount });
      console.log('Sent challenge to', opponent);
    } catch(err) {
      didSendChallenge.value = false;
      return reject(err);
    }

    const eventFilter = NewChallenge(null
                                   , wallet.address
                                   , opponent);
    lobbyContract.once(eventFilter, async id => {
      const gameId = BN.from(id).toNumber();
      console.log('Created challenge', gameId);
      didSendChallenge.value = false;
      await Promise.all([
        initGameData(gameId),
        refreshBalance()
      ]);
      lobby.newChallenge(gameId);
      playAudioClip('nes/NewChallenge');
      return resolve(gameId, opponent);
    });
  });

  const didAcceptChallenge = ref(false);
  const acceptChallenge = gameId => new Promise(async (resolve, reject) => {
    const gameContract = chessEngine(gameId);
    const { wagerAmount } = await gameContract.game(gameId);
    const deposited = await gameContract['balance(uint256)'](gameId);
    const deposit = BN.from(wagerAmount).sub(deposited);

    try {
      didAcceptChallenge.value = true;
      await gameContract.acceptChallenge(gameId, { value: deposit });
      console.log('Accepted challenge for game', gameId);
    } catch(err) {
      didAcceptChallenge.value = false;
      return reject(err);
    }

    const eventFilter = ChallengeAccepted(gameId, wallet.address);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Game', gameId, 'started with', opponent);
      didAcceptChallenge.value = false;
      await Promise.all([
        fetchGameData(gameId),
        refreshBalance()
      ]);
      lobby.newGame(gameId);
      playAudioClip('nes/NewChallenge');
      return resolve(gameId, opponent);
    });
  });

  const didDeclineChallenge = ref(false);
  const declineChallenge = gameId => new Promise(async (resolve, reject) => {
    const gameContract = chessEngine(gameId);

    try {
      didDeclineChallenge.value = true;
      await gameContract.declineChallenge(gameId);
      console.log('Declined challenge', gameId);
    } catch(err) {
      didDeclineChallenge.value = false;
      return reject(err);
    }

    const eventFilter = ChallengeDeclined(gameId);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge', gameId, 'was declined');
      didDeclineChallenge.value = false;
      await Promise.all([
        fetchGameData(gameId),
        refreshBalance()
      ]);
      lobby.popChallenge(gameId);
      playAudioClip('nes/Explosion');
      return resolve(gameId, opponent);
    });
  });

  const didModifyChallenge = ref(false);
  const modifyChallenge = (gameId, startAsWhite, timePerMove, wagerAmount) => new Promise(async (resolve, reject) => {
    const gameContract = chessEngine(gameId);
    const deposited = await gameContract['balance(uint256)'](gameId);
    const depositAmount = BN.from(wagerAmount).sub(deposited);

    try {
      didModifyChallenge.value = true;
      await gameContract.modifyChallenge(gameId
                                       , startAsWhite
                                       , timePerMove
                                       , wagerAmount
                                       , { value: depositAmount });
      console.log('Modified challenge', gameId);
    } catch(err) {
      didModifyChallenge.value = false;
      return reject(err);
    }

    const eventFilter = TouchRecord(gameId, wallet.address);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge updated', gameId);
      didModifyChallenge.value = false;
      await Promise.all([
        fetchGameData(gameId),
        refreshBalance()
      ]);
      playAudioClip('nes/NewChallenge');
      return resolve(gameId, opponent);
    });
  });

  const txPending = computed(() => {
    return didSendChallenge.value
        || didAcceptChallenge.value
        || didDeclineChallenge.value
        || didModifyChallenge.value;
  });

  // Incoming Events
  const recordUpdated = TouchRecord(null, null, wallet.address);
  const createdChallenge = NewChallenge(null, null, wallet.address);
  const declinedChallenge = ChallengeDeclined(null, null, wallet.address);
  const acceptedChallenge = ChallengeAccepted(null, null, wallet.address);
  const gameFinished = GameFinished(null, null, wallet.address);

  function createListeners() {
    console.log('Register listeners for incoming lobby events');

    lobbyContract.on(createdChallenge, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Received new challenge from', opponent);
      await initGameData(gameId);
      lobby.newChallenge(gameId);
      playAudioClip('nes/NewChallenge');
    });

    lobbyContract.on(acceptedChallenge, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Challenge', gameId, 'was accepted by', opponent);
      await fetchGameData(gameId);
      lobby.newGame(gameId);
      await refreshBalance();
      playAudioClip('nes/Berserk');
    });

    lobbyContract.on(declinedChallenge, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Challenge', gameId, 'was declined by', opponent);
      await fetchGameData(gameId);
      lobby.popChallenge(gameId);
      await refreshBalance();
      playAudioClip('nes/Explosion');
    });

    lobbyContract.on(gameFinished, async id => {
      const gameId = BN.from(id).toNumber();
      console.log('Game', gameId, 'finished');
      await fetchGameData(gameId);
      lobby.finishGame(id);
      await refreshBalance();
      playAudioClip('nes/Explosion');
    });

    // TouchedRecord Listener
    lobbyContract.on(recordUpdated, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Game', gameId, 'was touched by', opponent);
      await fetchGameData(gameId);
      playAudioClip('nes/Explosion');
    });
  }

  function destroyListeners() {
    lobbyContract.off(recordUpdated);
    lobbyContract.off(createdChallenge);
    lobbyContract.off(declinedChallenge);
    lobbyContract.off(acceptedChallenge);
    lobbyContract.off(gameFinished);
  }

  return {
    lobby,
    txPending,
    lobbyContract,
    chessEngine,
    initGameData,
    fetchGameData,
    fetchChessEngine,
    sendChallenge,
    acceptChallenge,
    declineChallenge,
    modifyChallenge,
    createListeners,
    destroyListeners
  };
}
