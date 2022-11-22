import _ from 'lodash';
import { ethers, Contract } from 'ethers';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useLobbyStore from '../store/lobby';

export default async function() {
  const { wallet, provider, signer } = await useWallet();

  const lobby = useLobbyStore();

  if (wallet.connected && !lobby.initialized) {
    await lobby.initialize();
  }

  const {
    TouchRecord,
    NewChallenge,
    ChallengeDeclined,
    ChallengeAccepted,
    GameFinished
  } = lobby.contract.filters;

  const didSendChallenge = ref(false);
  const sendChallenge = (opponent
                       , startAsWhite
                       , timePerMove
                       , wagerAmount
                       , wagerToken) => new Promise(async (resolve, reject) => {
    //try {
      await lobby.contract.challenge(opponent
                                   , startAsWhite
                                   , timePerMove
                                   , wagerAmount
                                 , { value: wagerAmount });
      console.log('Sent challenge to', opponent);
      didSendChallenge.value = true;
      const eventFilter = NewChallenge(null
                                     , wallet.address
                                     , opponent);
      lobby.contract.once(eventFilter, async id => {
        didSendChallenge.value = false;
        const gameId = await lobby.newChallenge(id);
        console.log('Created challenge', gameId);
        resolve(gameId, opponent);
      });
      /*
    } catch(err) {
      reject(err);
    }
    /**/
  });

  const didAcceptChallenge = ref(false);
  const acceptChallenge = gameId => new Promise(async (resolve, reject) => {
    const gameContract = lobby.chessEngine(gameId);
    await gameContract.acceptChallenge(gameId);
    didAcceptChallenge.value = true;
    console.log('Accepted challenge for game', gameId);
    const eventFilter = ChallengeAccepted(gameId, wallet.address);
    lobby.contract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Game', gameId, 'started with', opponent);
      didAcceptChallenge.value = false;
      await lobby.newGame(gameId);
      resolve(gameId, opponent);
    });
  });

  const didDeclineChallenge = ref(false);
  const declineChallenge = gameId => new Promise(async (resolve, reject) => {
    const gameContract = lobby.chessEngine(gameId);
    await gameContract.declineChallenge(gameId);
    didDeclineChallenge.value = true;
    console.log('Declined challenge', gameId);
    const eventFilter = ChallengeDeclined(gameId);
    lobby.contract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge', gameId, 'was declined');
      didDeclineChallenge.value = false;
      await lobby.popChallenge(gameId);
      resolve(gameId, opponent);
    });
  });

  const didModifyChallenge = ref(false);
  const modifyChallenge = (gameId, startAsWhite, timePerMove, wagerAmount) => new Promise(async (resolve, reject) => {
    const gameContract = lobby.chessEngine(gameId);
    await gameContract.modifyChallenge(gameId,
                                       startAsWhite,
                                       timePerMove,
                                       wagerAmount);
    console.log('Modified challenge', gameId);
    didModifyChallenge.value = true;
    const eventFilter = TouchRecord(gameId, wallet.address);
    lobby.contract.once(eventFilter, async (id, addr, opponent) => {
      console.log('Challenge updated', gameId);
      didModifyChallenge.value = false;
      await lobby.fetchMetadata(gameId);
      resolve(gameId, opponent);
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
    console.log('Listen for incoming lobby events');

    // CreatedChallenge Listener
    lobby.contract.on(createdChallenge, (id, opponent) => {
      console.log('Received challenge from', opponent);
      lobby.newChallenge(id);
    });

    // DeclinedChallenge Listener
    lobby.contract.on(acceptedChallenge, (id, opponent) => {
      console.log('Opponent accepted challenge', id.toNumber());
      lobby.newGame(id);
    });

    // DeclinedChallenge Listener
    lobby.contract.on(declinedChallenge, (id, opponent) => {
      console.log('Opponent declined challenge', id.toNumber());
      lobby.popChallenge(id);
    });

    // GameFinished Listener
    lobby.contract.on(gameFinished, (id, opponent) => {
      console.log('Game finished', id.toNumber());
      lobby.finishGame(id);
    });

    // TouchedRecord Listener
    lobby.contract.on(recordUpdated, (id, opponent) => {
      console.log('Opponent modified record for game', id.toNumber());
      lobby.fetchMetadata(id);
    });
  }

  function destroyListeners() {
    lobby.contract.off(recordUpdated);
    lobby.contract.off(createdChallenge);
    lobby.contract.off(declinedChallenge);
    lobby.contract.off(acceptedChallenge);
    lobby.contract.off(gameFinished);
  }

  return {
    lobby,
    txPending,
    sendChallenge,
    acceptChallenge,
    declineChallenge,
    modifyChallenge,
    createListeners,
    destroyListeners
  };
}
