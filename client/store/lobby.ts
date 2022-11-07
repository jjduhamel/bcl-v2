import _ from 'lodash';
import { ethers, Contract, BigNumber } from 'ethers';
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
    address() {
      // TODO Support other networks
      const config = useRuntimeConfig();
      return config.contractAddress.local;
    },
    contract() {
      const wallet = useWalletStore();
      return new Contract(this.address
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
    async _fetchEngine(gameId: number) {
      const lobby = this.contract;
      const contract = await lobby.chessEngine(gameId);
      this.contracts[gameId] = contract;
    },
    async _fetchMetadata(gameId: number) {
      const { opponentAddress } = useEthUtils();
      const engine = this.chessEngine(gameId);
      const [ ,
        state,
        outcome,
        whitePlayer,
        blackPlayer,
        currentMove,
        timePerMove,
        timeOfLastMove,
        wagerAmount ] = await engine.game(gameId);
      this.metadata[gameId] = {
        id: BigNumber.from(gameId).toNumber(),
        state,
        outcome,
        whitePlayer,
        blackPlayer,
        currentMove,
        ..._.mapValues({ timePerMove
                       , timeOfLastMove
                       , wagerAmount },
                       bn => bn.toString())
      };
    },
    async newChallenge(gameId) {
      const lobby = this.contract;
      await this._fetchEngine(gameId);
      await this._fetchMetadata(gameId);
      this.pending = [ ...this.pending, gameId ];
    },
    // FIXME gameId is BigNumber causing this to fail
    async popChallenge(gameId) {
      this.pending = _.without(this.pending, gameId);
    },
    async newGame(gameId) {
      const lobby = this.contract;
      await this._fetchEngine(gameId);
      await this._fetchMetadata(gameId);
      this.popChallenge(gameId);
      this.current.push(gameId);
    },
    async finishGame(gameId) {
      const lobby = this.contract;
      await this._fetchEngine(gameId);
      await this._fetchMetadata(gameId);
      this.current = _.without(this.current, gameId);
      this.history.push(gameId);
    },
    async fetchChallenges() {
      const lobby = this.contract;
      const challenges = await lobby.challenges();
      await Promise.all(_.map(challenges, this.newChallenge));
      this.pending = challenges;
      console.log('Fetched', challenges.length, 'challenges');
    },
    async fetchGames() {
      const lobby = this.contract;
      const games = await lobby.games();
      await Promise.all(_.map(games, this.newGame));
      this.current = games;
      console.log('Fetched', games.length, 'games');
    },
    async fetchHistory() {
      const lobby = this.contract;
      const games = await lobby.history();
      await Promise.all(_.map(games, this.finishGame));
      this.finished = games;
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
