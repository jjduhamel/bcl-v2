import _ from 'lodash';
import { BigNumber as BN } from 'ethers';
import { fetchSigner, getContract } from '@wagmi/core';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useLobbyStore from '../store/lobby';

export default async function() {
  const { $amplitude } = useNuxtApp();
  const { wallet, refreshBalance } = await useWallet();
  const { playAudioClip } = useAudioUtils();
  const lobby = useLobbyStore();

  if (!wallet.connected) throw Error('Wallet isn\'t connected');
  const signer = await fetchSigner();
  const lobbyContract = getContract({
    address: lobby.address,
    abi: LobbyContract.abi,
    signerOrProvider: signer
  });

  const {
    TouchRecord,
    NewChallenge,
    ChallengeDeclined,
    ChallengeAccepted,
    GameFinished
  } = lobbyContract.filters;

  async function initPlayerLobby() {
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
    return getContract({
      address: lobby.engineAddress(gameId),
      abi: EngineContract.abi,
      signerOrProvider: signer
    });
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
                       , wagerToken) =>
  new Promise(async (resolve, reject) => {
    try {
      didSendChallenge.value = true;
      $amplitude.track('SendChallenge', {
        opponent,
        startAsWhite,
        timePerMove,
        wagerAmount
      });
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
      $amplitude.track('ChallengeSent', { opponent, gameId });
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
    let deposit = BN.from(wagerAmount).sub(deposited);
    if (deposit.lt(0)) deposit = BN.from(0);
    console.log('Accept', gameId, deposit);

    try {
      didAcceptChallenge.value = true;
      $amplitude.track('AcceptChallenge', { gameId, deposit });
      await gameContract.acceptChallenge(gameId, { value: deposit });
      console.log('Accepted challenge for game', gameId);
    } catch(err) {
      didAcceptChallenge.value = false;
      return reject(err);
    }

    const eventFilter = ChallengeAccepted(gameId, wallet.address);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Game', gameId, 'started with', opponent);
      $amplitude.track('ChallengeAccepted', { gameId, opponent });
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
      $amplitude.track('DeclineChallenge', { gameId });
      await gameContract.declineChallenge(gameId);
      console.log('Declined challenge', gameId);
    } catch(err) {
      didDeclineChallenge.value = false;
      return reject(err);
    }

    const eventFilter = ChallengeDeclined(gameId);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge', gameId, 'was declined');
      $amplitude.track('ChallengeDeclined', { gameId, opponent });
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
    let deposit = BN.from(wagerAmount).sub(deposited);
    if (deposit.lt(0)) deposit = BN.from(0);

    try {
      didModifyChallenge.value = true;
      $amplitude.track('ModifyChallenge', {
        gameId,
        startAsWhite,
        timePerMove,
        wager: wagerAmount,
        deposit
      });
      await gameContract.modifyChallenge(gameId
                                       , startAsWhite
                                       , timePerMove
                                       , wagerAmount
                                       , { value: deposit });
      console.log('Modified challenge', gameId);
    } catch(err) {
      didModifyChallenge.value = false;
      return reject(err);
    }

    const eventFilter = TouchRecord(gameId, wallet.address);
    lobbyContract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge updated', gameId);
      didModifyChallenge.value = false;
      $amplitude.track('ChallengeModified', { gameId, opponent });
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
      $amplitude.track('ChallengeCreated', { gameId, opponent });
      await initGameData(gameId);
      lobby.newChallenge(gameId);
      playAudioClip('nes/NewChallenge');
    });

    lobbyContract.on(acceptedChallenge, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Challenge', gameId, 'was accepted by', opponent);
      $amplitude.track('ChallengeAccepted', { gameId, opponent });
      await fetchGameData(gameId);
      lobby.newGame(gameId);
      await refreshBalance();
      playAudioClip('nes/Berserk');
    });

    lobbyContract.on(declinedChallenge, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Challenge', gameId, 'was declined by', opponent);
      $amplitude.track('ChallengeDeclined', { gameId, opponent });
      await fetchGameData(gameId);
      lobby.popChallenge(gameId);
      await refreshBalance();
      playAudioClip('nes/Explosion');
    });

    lobbyContract.on(gameFinished, async id => {
      const gameId = BN.from(id).toNumber();
      console.log('Game', gameId, 'finished');
      $amplitude.track('GameFinished', { gameId });
      await fetchGameData(gameId);
      lobby.finishGame(id);
      await refreshBalance();
      playAudioClip('nes/Explosion');
    });

    // TouchedRecord Listener
    lobbyContract.on(recordUpdated, async (id, opponent) => {
      const gameId = BN.from(id).toNumber();
      console.log('Game', gameId, 'was touched by', opponent);
      $amplitude.track('ChallengeModified', { gameId, opponent });
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
    initPlayerLobby,
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
