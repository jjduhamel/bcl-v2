import _ from 'lodash';
import { ethers, Contract, BigNumber as BN } from 'ethers';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useWalletStore from './wallet';

export default defineStore('lobby', {
  state: () => {
    return {
      initializing: false,
      initialized: false,
      pending: [] as number,
      current: [] as number,
      finished: [] as number,
      contracts: {} as string,
      metadata: {} as GameInfo
    }
  },
  getters: {
    challenges() {
      return _.map(this.pending, gameId => this.gameData(gameId));
    },
    games() {
      return _.map(this.current, gameId => this.gameData(gameId));
    },
    history() {
      return _.map(this.finished, gameId => this.gameData(gameId));
    },
    lobbyAddress() {
      const config = useRuntimeConfig();
      const wallet = useWalletStore();
      switch (wallet.network) {
        case 'homestead': return config.lobbyAddress.ethereum;
        case 'goerli': return config.lobbyAddress.goerli;
        case 'matic': return config.lobbyAddress.matic;
        case 'maticmum': return config.lobbyAddress.mumbai;
        default: return config.lobbyAddress.local;
      }
      return config.lobbyAddress.local;
    },
    contract() {
      const wallet = useWalletStore();
      return new Contract(this.lobbyAddress
                        , LobbyContract.abi
                        , wallet.signer || wallet.provider);
    }
  },
  actions: {
    async initialize() {
      const wallet = useWalletStore();
      if (this.initialized) throw new Error('Already initialized');
      if (!wallet.connected) throw new Error('Wallet not connected');
      console.log('Initialize lobby store');
      this.initialized = true;
      await Promise.all([
        this.fetchChallenges(),
        this.fetchGames(),
        this.fetchHistory()
      ]);
    },
    async fetchEngine(gameId: number) {
      const lobby = this.contract;
      const contract = await lobby.chessEngine(gameId);
      this.contracts[gameId] = contract;
    },
    async fetchMetadata(id: number) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      console.log('Update metadata for game', gameId);
      const { opponentAddress } = useEthUtils();
      const engine = this.chessEngine(gameId);
      const [
        , state
        , outcome
        , whitePlayer
        , blackPlayer
        , currentMove
        , timePerMove
        , timeOfLastMove
        , wagerAmount
      ] = await engine.game(gameId);
      this.metadata[gameId] = {
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
    },
    async newChallenge(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      console.log('Register new challenge', gameId);
      const lobby = this.contract;
      await this.fetchEngine(gameId);
      await this.fetchMetadata(gameId);
      this.pending = _.union(this.pending, [ gameId ]);
      return gameId;
    },
    async popChallenge(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      const len = this.pending.length;
      this.pending = _.without(this.pending, gameId);
      if (this.pending.length < len) console.log('Unregistered challenge', gameId);
      return gameId;
    },
    async newGame(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      console.log('Register new game', gameId);
      const lobby = this.contract;
      await this.fetchEngine(gameId);
      await this.fetchMetadata(gameId);
      this.popChallenge(gameId);
      this.current = _.union(this.current, [ gameId ]);
      return gameId;
    },
    async finishGame(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      console.log('Unregister game', gameId);
      const lobby = this.contract;
      await this.fetchEngine(gameId);
      await this.fetchMetadata(gameId);
      this.current = _.without(this.current, gameId);
      this.finished = _.union(this.finished, [ gameId ]);
    },
    async fetchChallenges() {
      const lobby = this.contract;
      const challenges = await lobby.challenges();
      await Promise.all(_.map(challenges, this.newChallenge));
      console.log('Fetched', challenges.length, 'challenges');
    },
    async fetchGames() {
      const lobby = this.contract;
      const games = await lobby.games();
      await Promise.all(_.map(games, this.newGame));
      console.log('Fetched', games.length, 'games');
    },
    async fetchHistory() {
      const lobby = this.contract;
      const games = await lobby.history();
      await Promise.all(_.map(games, this.finishGame));
      console.log('Fetched', games.length, 'finished games');
    },
    chessEngine(gameId: number) {
      const wallet = useWalletStore();
      const contract = this.contracts[gameId];
      const out = new Contract(contract
                        , EngineContract.abi
                        , wallet.signer || wallet.provider);
      return out;
    },
    opponent(gameId: number) {
      const wallet = useWalletStore();
      const { whitePlayer, blackPlayer } = this.metadata[gameId];
      switch (wallet.address) {
        case whitePlayer: return blackPlayer;
        case blackPlayer: return whitePlayer;
        default: throw Error('Not a player');
      }
    },
    isWhitePlayer(gameId: number) {
      const wallet = useWalletStore();
      const { whitePlayer } = this.metadata[gameId];
      return wallet.address == whitePlayer;
    },
    isCurrentMove(gameId: number) {
      const wallet = useWalletStore();
      const { currentMove } = this.metadata[gameId];
      return wallet.address == currentMove;
    },
    gameData(gameId: number) {
      return {
        ...this.metadata[gameId],
        opponent: this.opponent(gameId),
        isWhitePlayer: this.isWhitePlayer(gameId),
        isCurrentMove: this.isCurrentMove(gameId)
      };
    }
  }
});

interface GameInfo {
  id: number,
  outcome: number,
  whitePlayer: string,
  blackPlayer: string,
  currentMove: string,
  timePerMove: number,
  timeOfLastMove: number | null,
  wagerAmount: number
}
