import _ from 'lodash';
import { BigNumber as BN, constants } from 'ethers';
import { fetchSigner, getContract } from '@wagmi/core';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useLobbyStore from '../store/lobby';
import useLoungeStore from '../store/lounge';

export default async function() {
  const { $amplitude } = useNuxtApp();
  const { wallet, refreshBalance } = await useWallet();
  const { playAudioClip } = useAudioUtils();
  const lobby = useLobbyStore();
  const lounge = useLoungeStore();

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

  async function isAgent(address) {
    try {
      const { owner } = await lobbyContract.agentProfile(address);
      return owner !== constants.AddressZero;
    } catch {
      return false; // agentProfile reverts Unregistered() for non-agents
    }
  }

  // The lobby's per-player views (challenges/games/history) double as global
  // enumerators when called with address(0): the contract adds every gameId to
  // address(0)'s sets too. Reuse that surface for the public Lounge feeds.
  async function fetchOpenTables() {
    const ids = await lobbyContract.challenges(constants.AddressZero);
    await Promise.all(_.map(ids, initGameData));
    lounge.tables = _.map(ids, id => id.toNumber());
    console.log('Synced', lounge.tables.length, 'open tables');
    return lounge.tables;
  }

  async function fetchActiveGames() {
    const ids = await lobbyContract.games(constants.AddressZero);
    await Promise.all(_.map(ids, initGameData));
    lounge.games = _.map(ids, id => id.toNumber());
    console.log('Synced', lounge.games.length, 'active games');
    return lounge.games;
  }

  // playerProfile reverts Unregistered() until registerPlayer is called; surface
  // that as null so the page can gate the challenge form before submitting.
  // ethers v5 returns uint ≤ 48 bits as a plain number, not BigNumber, so coerce
  // with Number() rather than .toNumber() — createdAt is uint40.
  async function fetchPlayerProfile() {
    try {
      const p = await lobbyContract.playerProfile(wallet.address);
      lobby.playerProfile = {
        username: p.username,
        avatar: p.avatar,
        createdAt: Number(p.createdAt)
      };
    } catch {
      lobby.playerProfile = null;
    }
    return lobby.playerProfile;
  }

  // Resolve an arbitrary address to whichever profile shape the contract holds —
  // agent first (its `owner` field is the discriminator ProfileForm reads), then
  // player. Falls back to an empty player shape (createdAt=0) for unregistered
  // addresses so the view can render Status: Unregistered. `agentProfile`
  // doesn't revert for a registered human (its isRegistered guard passes on
  // either profile), so check owner != address(0) before treating it as agent.
  async function fetchProfile(address) {
    try {
      const p = await lobbyContract.agentProfile(address);
      if (p.owner !== constants.AddressZero) return {
        address,
        owner: p.owner,
        active: p.active,
        nickname: p.nickname,
        avatar: p.avatar,
        createdAt: Number(p.createdAt)
      };
    } catch {}
    try {
      const p = await lobbyContract.playerProfile(address);
      return {
        address,
        username: p.username,
        avatar: p.avatar,
        createdAt: Number(p.createdAt)
      };
    } catch {}
    return { address, username: '', avatar: '', createdAt: 0 };
  }

  async function fetchAgents(address) {
    const agentAddresses = await lobbyContract.agents(address);
    // Stats moved off RobotProfile in M2; gameStats(addr) is the new accessor.
    const [profiles, stats, codes] = await Promise.all([
      Promise.all(_.map(agentAddresses, addr => lobbyContract.agentProfile(addr))),
      Promise.all(_.map(agentAddresses, addr => lobbyContract.gameStats(addr))),
      Promise.all(_.map(agentAddresses, addr => signer.provider.getCode(addr)))
    ]);
    return _.map(_.zip(agentAddresses, profiles, stats, codes), ([agentAddress, p, s, code]) => ({
      address: agentAddress,
      delegated: code.startsWith('0xef0100'),
      ..._.pick(p, [ 'active', 'owner', 'nickname', 'avatar' ]),
      wins: s.victories.toNumber(),
      losses: s.defeats.toNumber(),
      draws: s.draws.toNumber(),
      games: s.finished.toNumber()
    }));
  }

  async function initPlayerLobby() {
    console.log('Initialize player lobby', lobby.address);

    // Lobby reads (challenges/games/history/agents) all gate on isRegistered,
    // so probe the profile first and short-circuit when the wallet hasn't
    // registered yet — the page surfaces the registration prompt.
    await fetchPlayerProfile();
    if (!lobby.playerProfile) {
      console.log('Wallet not registered; lobby reads skipped');
      lobby.initialized = true;
      return;
    }

    const [ challenges, games, history, agents ] = await Promise.all([
      lobbyContract.challenges(wallet.address),
      lobbyContract.games(wallet.address),
      lobbyContract.history(wallet.address),
      fetchAgents(wallet.address)
    ]);

    const [ agentChallenges, agentGames, agentHistory ] = (await Promise.all([
      Promise.all(_.map(agents, agent => lobbyContract.challenges(agent.address))),
      Promise.all(_.map(agents, agent => lobbyContract.games(agent.address))),
      Promise.all(_.map(agents, agent => lobbyContract.history(agent.address)))
    ])).map(_.flatten);

    await Promise.all(_.map([
      ...challenges,
      ...games,
      ...history,
      ...agentChallenges,
      ...agentGames,
      ...agentHistory
    ], initGameData));

    lobby.agents = agents;
    console.log('Synced', agents.length, 'agents');
    lobby.pending = _.map([ ...challenges, ...agentChallenges ], gameId => gameId.toNumber());
    console.log('Synced', lobby.challenges.length, 'challenges');
    lobby.current = _.map([ ...games, ...agentGames ], gameId => gameId.toNumber());
    console.log('Synced', lobby.games.length, 'games');
    lobby.finished = _.map([ ...history, ...agentHistory ], gameId => gameId.toNumber());
    console.log('Synced', lobby.history.length, 'finished games');

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

    lounge.metadata[gameId] = {
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
  const sendChallenge = (sender
                       , opponent
                       , startAsWhite
                       , timePerMove
                       , wagerAmount) =>
  new Promise(async (resolve, reject) => {
    try {
      didSendChallenge.value = true;
      $amplitude.track('SendChallenge', {
        sender,
        opponent,
        startAsWhite,
        timePerMove,
        wagerAmount
      });
      await lobbyContract.challenge(sender
                                  , opponent
                                  , startAsWhite
                                  , timePerMove
                                  , wagerAmount
                                  , constants.AddressZero
                                , { value: wagerAmount });
      console.log('Sent challenge to', opponent);
    } catch(err) {
      didSendChallenge.value = false;
      return reject(err);
    }

    const eventFilter = NewChallenge(null
                                   , sender
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

  const didCreateTable = ref(false);
  const createTable = (sender, startAsWhite, timePerMove, wagerAmount) =>
  new Promise(async (resolve, reject) => {
    try {
      didCreateTable.value = true;
      $amplitude.track('CreateTable', { sender, startAsWhite, timePerMove, wagerAmount });
      await lobbyContract.createTable(sender
                                    , startAsWhite
                                    , timePerMove
                                    , wagerAmount
                                    , constants.AddressZero
                                  , { value: wagerAmount });
      console.log('Created open table');
    } catch(err) {
      didCreateTable.value = false;
      return reject(err);
    }

    // Open tables emit NewChallenge with opponent = address(0).
    const eventFilter = NewChallenge(null, sender, constants.AddressZero);
    lobbyContract.once(eventFilter, async id => {
      const gameId = BN.from(id).toNumber();
      console.log('Created open table', gameId);
      $amplitude.track('TableCreated', { gameId });
      didCreateTable.value = false;
      await Promise.all([initGameData(gameId), refreshBalance()]);
      lobby.newChallenge(gameId);
      lounge.tables = _.union(lounge.tables, [ gameId ]);
      playAudioClip('nes/NewChallenge');
      return resolve(gameId);
    });
  });

  const didAcceptChallenge = ref(false);
  const acceptChallenge = gameId => new Promise(async (resolve, reject) => {
    const gameContract = chessEngine(gameId);
    const { wagerAmount } = await gameContract.game(gameId);
    const deposited = await lobbyContract.currentDeposit(gameId);
    let deposit = BN.from(wagerAmount).sub(deposited);
    if (deposit.lt(0)) deposit = BN.from(0);
    console.log('Accept', gameId, deposit);

    try {
      didAcceptChallenge.value = true;
      $amplitude.track('AcceptChallenge', { gameId, deposit });
      await lobbyContract.acceptChallenge(gameId, { value: deposit });
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

  const didJoinTable = ref(false);
  const joinTable = (gameId, sender, startAsWhite) => new Promise(async (resolve, reject) => {
    const gameContract = chessEngine(gameId);
    // currentDeposit is gated by isPlayersGame and the joiner isn't a player
    // yet; they have no prior deposit on this game so just pay the full wager.
    const { wagerAmount } = await gameContract.game(gameId);

    try {
      didJoinTable.value = true;
      $amplitude.track('JoinTable', { gameId, sender, startAsWhite, wagerAmount });
      await lobbyContract.joinTable(gameId, sender, startAsWhite, { value: wagerAmount });
      console.log('Joined table', gameId);
    } catch(err) {
      didJoinTable.value = false;
      return reject(err);
    }

    // joinTable runs through _modify and fires TouchRecord(gameId, sender, creator).
    const eventFilter = TouchRecord(gameId, sender);
    lobbyContract.once(eventFilter, async (id, addr, creator) => {
      console.log('Joined table', gameId, 'opened by', creator);
      $amplitude.track('TableJoined', { gameId, creator });
      didJoinTable.value = false;
      await Promise.all([fetchGameData(gameId), refreshBalance()]);
      lounge.tables = _.without(lounge.tables, gameId);
      lobby.newChallenge(gameId);
      playAudioClip('nes/NewChallenge');
      return resolve(gameId, creator);
    });
  });

  const didDeclineChallenge = ref(false);
  const declineChallenge = gameId => new Promise(async (resolve, reject) => {
    try {
      didDeclineChallenge.value = true;
      $amplitude.track('DeclineChallenge', { gameId });
      await lobbyContract.declineChallenge(gameId);
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
  const modifyChallenge = (gameId, sender, startAsWhite, timePerMove, wagerAmount) => new Promise(async (resolve, reject) => {
    const deposited = await lobbyContract.currentDeposit(gameId);
    let deposit = BN.from(wagerAmount).sub(deposited);
    if (deposit.lt(0)) deposit = BN.from(0);

    try {
      didModifyChallenge.value = true;
      $amplitude.track('ModifyChallenge', {
        gameId,
        sender,
        startAsWhite,
        timePerMove,
        wager: wagerAmount,
        deposit
      });
      await lobbyContract.modifyChallenge(gameId
                                        , sender
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

  const didUpdateAgent = ref(false);
  const updateAgent = (robot, nickname, avatar) => new Promise(async (resolve, reject) => {
    try {
      didUpdateAgent.value = true;
      await lobbyContract.updateAgent(robot, nickname, avatar, '', '', '');
      console.log('Updating agent', robot);
    } catch(err) {
      didUpdateAgent.value = false;
      return reject(err);
    }

    const eventFilter = lobbyContract.filters.AgentUpdated(wallet.address, robot);
    lobbyContract.once(eventFilter, async (owner, agent) => {
      console.log('Agent updated', agent);
      didUpdateAgent.value = false;
      lobby.agents = await fetchAgents(wallet.address);
      return resolve(agent);
    });
  });

  const didSuspendAgent = ref(false);
  const suspendAgent = robot => new Promise(async (resolve, reject) => {
    try {
      didSuspendAgent.value = true;
      await lobbyContract.suspendAgent(robot);
      console.log('Suspending agent', robot);
    } catch(err) {
      didSuspendAgent.value = false;
      return reject(err);
    }

    const eventFilter = lobbyContract.filters.AgentSuspended(wallet.address, robot);
    lobbyContract.once(eventFilter, async (owner, agent) => {
      console.log('Agent suspended', agent);
      didSuspendAgent.value = false;
      lobby.agents = await fetchAgents(wallet.address);
      return resolve(agent);
    });
  });

  const didResumeAgent = ref(false);
  const resumeAgent = robot => new Promise(async (resolve, reject) => {
    try {
      didResumeAgent.value = true;
      await lobbyContract.resumeAgent(robot);
      console.log('Resuming agent', robot);
    } catch(err) {
      didResumeAgent.value = false;
      return reject(err);
    }

    const eventFilter = lobbyContract.filters.AgentResumed(wallet.address, robot);
    lobbyContract.once(eventFilter, async (owner, agent) => {
      console.log('Agent resumed', agent);
      didResumeAgent.value = false;
      lobby.agents = await fetchAgents(wallet.address);
      return resolve(agent);
    });
  });

  const didUnregisterAgent = ref(false);
  const unregisterAgent = robot => new Promise(async (resolve, reject) => {
    try {
      didUnregisterAgent.value = true;
      await lobbyContract.unregisterAgent(robot);
      console.log('Unregistering agent', robot);
    } catch(err) {
      didUnregisterAgent.value = false;
      return reject(err);
    }

    const eventFilter = lobbyContract.filters.AgentUnregistered(wallet.address, robot);
    lobbyContract.once(eventFilter, async (owner, agent) => {
      console.log('Agent unregistered', agent);
      didUnregisterAgent.value = false;
      lobby.agents = await fetchAgents(wallet.address);
      return resolve(agent);
    });
  });

  const didRegisterPlayer = ref(false);
  const registerPlayer = (username, avatar) => new Promise(async (resolve, reject) => {
    try {
      didRegisterPlayer.value = true;
      // No PlayerRegistered event; await the receipt and re-read the profile.
      const tx = await lobbyContract.registerPlayer(wallet.address, username, avatar);
      await tx.wait();
      console.log('Registered player', wallet.address);
      $amplitude.track('PlayerRegistered', { username });
      await fetchPlayerProfile();
      didRegisterPlayer.value = false;
      return resolve(lobby.playerProfile);
    } catch(err) {
      didRegisterPlayer.value = false;
      return reject(err);
    }
  });

  const didRegisterAgent = ref(false);
  const registerAgent = (robot, nickname, avatar) => new Promise(async (resolve, reject) => {
    try {
      didRegisterAgent.value = true;
      await lobbyContract.registerAgent(robot, nickname, avatar, '', '', '');
      console.log('Registering agent', robot);
    } catch(err) {
      didRegisterAgent.value = false;
      return reject(err);
    }

    const eventFilter = lobbyContract.filters.AgentRegistered(wallet.address, robot);
    lobbyContract.once(eventFilter, async (owner, agent) => {
      console.log('Agent registered', agent);
      didRegisterAgent.value = false;
      lobby.agents = await fetchAgents(wallet.address);
      return resolve(agent);
    });
  });

  const txPending = computed(() => {
    return didSendChallenge.value
        || didCreateTable.value
        || didJoinTable.value
        || didAcceptChallenge.value
        || didDeclineChallenge.value
        || didModifyChallenge.value
        || didRegisterPlayer.value
        || didRegisterAgent.value
        || didUpdateAgent.value
        || didSuspendAgent.value
        || didResumeAgent.value
        || didUnregisterAgent.value;
  });

  // Incoming Events. Handlers are stable consts so off(filter, handler) can
  // remove them, and because each is bound to more than one filter below.
  const onCreatedChallenge = async (id, opponent) => {
    const gameId = BN.from(id).toNumber();
    console.log('Received new challenge from', opponent);
    $amplitude.track('ChallengeCreated', { gameId, opponent });
    await initGameData(gameId);
    lobby.newChallenge(gameId);
    playAudioClip('nes/NewChallenge');
  };

  const onAcceptedChallenge = async (id, opponent) => {
    const gameId = BN.from(id).toNumber();
    console.log('Challenge', gameId, 'was accepted by', opponent);
    $amplitude.track('ChallengeAccepted', { gameId, opponent });
    await fetchGameData(gameId);
    lobby.newGame(gameId);
    await refreshBalance();
    playAudioClip('nes/Berserk');
  };

  const onDeclinedChallenge = async (id, opponent) => {
    const gameId = BN.from(id).toNumber();
    console.log('Challenge', gameId, 'was declined by', opponent);
    $amplitude.track('ChallengeDeclined', { gameId, opponent });
    await fetchGameData(gameId);
    lobby.popChallenge(gameId);
    await refreshBalance();
    playAudioClip('nes/Explosion');
  };

  const onGameFinished = async id => {
    const gameId = BN.from(id).toNumber();
    console.log('Game', gameId, 'finished');
    $amplitude.track('GameFinished', { gameId });
    await fetchGameData(gameId);
    lobby.finishGame(id);
    await refreshBalance();
    playAudioClip('nes/Explosion');
  };

  const onRecordUpdated = async (id, opponent) => {
    const gameId = BN.from(id).toNumber();
    console.log('Game', gameId, 'was touched by', opponent);
    $amplitude.track('ChallengeModified', { gameId, opponent });
    await fetchGameData(gameId);
    playAudioClip('nes/Explosion');
  };

  const activeListeners = [];

  function createListeners() {
    console.log('Register listeners for incoming lobby events');
    const agents = _.map(lobby.agents, 'address');
    const recv = [ wallet.address, ...agents ];
    const add = (filter, handler) => {
      lobbyContract.on(filter, handler);
      activeListeners.push({ filter, handler });
    };

    // Receiver side: events targeting the wallet or any owned agent.
    add(NewChallenge(null, null, recv), onCreatedChallenge);
    add(ChallengeAccepted(null, null, recv), onAcceptedChallenge);
    add(ChallengeDeclined(null, null, recv), onDeclinedChallenge);
    add(TouchRecord(null, null, recv), onRecordUpdated);

    // GameFinished is color-keyed (white, black) with no once() handler, so
    // match wallet + agents on both seats.
    add(GameFinished(null, null, recv), onGameFinished);
    add(GameFinished(null, recv, null), onGameFinished);

    // Sender side, agents only: agents act from the MCP server with no local
    // once(); the wallet's own actions are covered by the per-action once()s.
    if (agents.length) {
      add(NewChallenge(null, agents, null), onCreatedChallenge);
      add(ChallengeAccepted(null, agents, null), onAcceptedChallenge);
      add(ChallengeDeclined(null, agents, null), onDeclinedChallenge);
      add(TouchRecord(null, agents, null), onRecordUpdated);
    }
  }

  function destroyListeners() {
    for (const { filter, handler } of activeListeners)
      lobbyContract.off(filter, handler);
    activeListeners.length = 0;
  }

  return {
    lobby,
    lounge,
    txPending,
    lobbyContract,
    chessEngine,
    initPlayerLobby,
    initGameData,
    fetchGameData,
    fetchChessEngine,
    fetchAgents,
    fetchOpenTables,
    fetchActiveGames,
    fetchPlayerProfile,
    fetchProfile,
    isAgent,
    sendChallenge,
    createTable,
    joinTable,
    acceptChallenge,
    declineChallenge,
    modifyChallenge,
    registerPlayer,
    registerAgent,
    updateAgent,
    suspendAgent,
    resumeAgent,
    unregisterAgent,
    createListeners,
    destroyListeners
  };
}
