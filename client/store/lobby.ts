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
    address() {
      const config = useRuntimeConfig();
      const wallet = useWalletStore();
      switch (wallet.network) {
        case 'homestead': return config.lobbyAddress.ethereum;
        case 'goerli': return config.lobbyAddress.goerli;
        case 'matic': return config.lobbyAddress.matic;
        case 'maticmum': return config.lobbyAddress.mumbai;
        default: return config.lobbyAddress.local;
      }
    },
    challenges() {
      return _.map(this.pending, gameId => this.gameData(gameId));
    },
    games() {
      return _.map(this.current, gameId => this.gameData(gameId));
    },
    history() {
      return _.map(this.finished, gameId => this.gameData(gameId));
    },
  },
  actions: {
    has(id) {
      const gameId = BN.from(id).toNumber();
      return (!_.isNil(this.metadata[gameId]));
    },
    newChallenge(id) {
      const gameId = BN.from(id).toNumber();
      console.log('Register new challenge', gameId);
      this.pending = _.union(this.pending, [ gameId ]);
      return gameId;
    },
    popChallenge(id) {
      const gameId = BN.from(id).toNumber();
      const pendingLen = this.pending.length;
      this.pending = _.without(this.pending, gameId);
      if (this.pending.length < pendingLen) console.log('Unregistered challenge', gameId);
      return gameId;
    },
    newGame(id) {
      const gameId = BN.from(id).toNumber();
      console.log('Register new game', gameId);
      this.popChallenge(gameId);
      this.current = _.union(this.current, [ gameId ]);
      return gameId;
    },
    finishGame(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      console.log('Unregister game', gameId);
      this.current = _.without(this.current, gameId);
      this.finished = _.union(this.finished, [ gameId ]);
    },
    engineAddress(id) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      const address = this.contracts[gameId];
      if (!address) throw new Error('MissingRecord');
      return address;
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
