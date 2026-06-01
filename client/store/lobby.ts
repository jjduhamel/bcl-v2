import _ from 'lodash';
import { constants, BigNumber as BN } from 'ethers';
import useWalletStore from './wallet';

export default defineStore('lobby', {
  state: () => {
    return {
      initializing: false,
      initialized: false,
      __profile: null as PlayerProfile | null,
      __agents: [] as AgentInfo[],
      __games: {} as GameInfo,   // gameId -> game data
      __engines: {} as string,   // gameId -> engine address
    }
  },
  getters: {
    address() {
      return useRuntimeConfig().lobbyAddress;
    },
    isRegistered(): boolean {
      return this.__profile !== null;
    },
    playerProfile() {
      return this.__profile;
    },
    agents() {
      return this.__agents;
    },
    challenges() {
      return _.filter(this.__games, g => g && this.isPending(g.id) && this.isPlayer(g.id))
              .map(g => this.gameData(g.id));
    },
    games() {
      return _.filter(this.__games, g => g && this.isActive(g.id) && this.isPlayer(g.id))
              .map(g => this.gameData(g.id));
    },
    history() {
      return _.filter(this.__games, g => g && this.isFinished(g.id) && this.isPlayer(g.id))
              .map(g => this.gameData(g.id));
    },
    // Global feeds for the public lounge (every player).
    activeGames() {
      return _.filter(this.__games, g => g && this.isActive(g.id))
              .map(g => this.gameData(g.id));
    },
    openTables() {
      return _.filter(this.__games, g => g && this.isPending(g.id) && this.isOpenTable(g.id))
              .map(g => this.gameData(g.id));
    },
  },
  actions: {
    has(id: number) {
      const gameId = BN.from(id).toNumber();
      return !_.isNil(this.__games[gameId]);
    },
    engineAddress(id: number) {
      const gameId = BN.isBigNumber(id) ? id.toNumber() : id;
      const address = this.__engines[gameId];
      if (!address) throw new Error('MissingRecord');
      return address;
    },
    controls(address: string) {
      const wallet = useWalletStore();
      return address === wallet.address
          || _.some(this.__agents, { address });
    },
    isOwnedAgent(address: string) {
      return _.some(this.__agents, { address });
    },
    ownedAgent(address: string) {
      return _.find(this.__agents, { address });
    },
    isPlayer(gameId: number) {
      const { whitePlayer, blackPlayer } = this.__games[gameId];
      return this.controls(whitePlayer) || this.controls(blackPlayer);
    },
    isWhitePlayer(gameId: number) {
      return this.controls(this.__games[gameId].whitePlayer);
    },
    player(gameId: number) {
      const { whitePlayer, blackPlayer } = this.__games[gameId];
      if (this.controls(whitePlayer)) return whitePlayer;
      if (this.controls(blackPlayer)) return blackPlayer;
      return null;  // spectator — not seated in this game
    },
    opponent(gameId: number) {
      const { whitePlayer, blackPlayer } = this.__games[gameId];
      if (this.controls(whitePlayer)) return blackPlayer;
      if (this.controls(blackPlayer)) return whitePlayer;
      return null;  // spectator — not seated in this game
    },
    isOpenTable(gameId: number) {
      const game = this.__games[gameId];
      return game.whitePlayer == constants.AddressZero
          || game.blackPlayer == constants.AddressZero;
    },
    isOwnOpenTable(gameId: number) {
      return this.isOpenTable(gameId) && this.isPlayer(gameId);
    },
    isCurrentMove(gameId: number) {
      return this.controls(this.__games[gameId]?.currentMove);
    },
    // GameState enum: Pending 0, Declined 1, Started 2, Draw 3, Finished 4,
    // Review 5, Migrated 6 (contracts/src/IChessEngine.sol).
    isPending(gameId: number) {
      return this.__games[gameId]?.state === 0;
    },
    isDeclined(gameId: number) {
      return this.__games[gameId]?.state === 1;
    },
    isActive(gameId: number) {
      const state = this.__games[gameId]?.state;
      return state === 2 || state === 5;  // Started or under Review
    },
    isFinished(gameId: number) {
      const state = this.__games[gameId]?.state;
      return state === 3 || state === 4;  // Draw or Finished
    },
    isInReview(gameId: number) {
      return this.__games[gameId]?.state === 5;
    },
    gameData(gameId: number) {
      return {
        ...this.__games[gameId],
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

interface GameInfo {
  id: number,
  state: number,
  outcome: number,
  whitePlayer: string,
  blackPlayer: string,
  currentMove: string,
  timePerMove: number,
  timeOfLastMove: number | null,
  wagerAmount: number
}

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
