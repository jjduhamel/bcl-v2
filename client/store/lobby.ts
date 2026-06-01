import _ from 'lodash';
import { ethers, Contract, BigNumber as BN } from 'ethers';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useWalletStore from './wallet';
import useLoungeStore from './lounge';

export default defineStore('lobby', {
  state: () => {
    return {
      initializing: false,
      initialized: false,
      playerProfile: null as PlayerProfile | null,
      agents: [] as AgentInfo[],
      pending: [] as number,
      current: [] as number,
      finished: [] as number,
      contracts: {} as string,
    }
  },
  getters: {
    address() {
      return useRuntimeConfig().lobbyAddress;
    },
    isRegistered(): boolean {
      return this.playerProfile !== null;
    },
    // Per-game metadata lives on the lounge store (shared with the spectator
    // feeds). Forwarding it as a getter keeps every `this.metadata[id]` site
    // in lobby's actions unchanged.
    metadata() {
      return useLoungeStore().metadata;
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
    controls(seat: string) {
      const wallet = useWalletStore();
      return seat === wallet.address || _.some(this.agents, { address: seat });
    },
    isOwnedAgent(seat: string) {
      return _.some(this.agents, { address: seat });
    },
    ownedAgent(seat: string) {
      return _.find(this.agents, { address: seat });
    },
    opponent(gameId: number) {
      const { whitePlayer, blackPlayer } = this.metadata[gameId];
      if (this.controls(whitePlayer)) return blackPlayer;
      if (this.controls(blackPlayer)) return whitePlayer;
      return null;  // spectator — not seated in this game
    },
    player(gameId: number) {
      const { whitePlayer, blackPlayer } = this.metadata[gameId];
      if (this.controls(whitePlayer)) return whitePlayer;
      if (this.controls(blackPlayer)) return blackPlayer;
      return null;  // spectator — not seated in this game
    },
    isPlayer(gameId: number) {
      const { whitePlayer, blackPlayer } = this.metadata[gameId];
      return this.controls(whitePlayer) || this.controls(blackPlayer);
    },
    isWhitePlayer(gameId: number) {
      return this.controls(this.metadata[gameId].whitePlayer);
    },
    isCurrentMove(gameId: number) {
      return this.controls(this.metadata[gameId].currentMove);
    },
    isInReview(gameId: number) {
      return this.metadata[gameId]?.state === 5;  // GameState.Review
    },
    gameData(gameId: number) {
      return {
        ...this.metadata[gameId],
        opponent: this.opponent(gameId),
        player: this.player(gameId),
        isPlayer: this.isPlayer(gameId),
        isWhitePlayer: this.isWhitePlayer(gameId),
        isCurrentMove: this.isCurrentMove(gameId),
        isInReview: this.isInReview(gameId)
      };
    }
  }
});

interface PlayerProfile {
  username: string,
  avatar: string,
  createdAt: number
}

interface AgentInfo {
  address: string,
  owner: string,
  nickname: string,
  avatar: string,
  active: boolean,
  delegated: boolean,
  wins: number,
  losses: number,
  draws: number,
  games: number
}
