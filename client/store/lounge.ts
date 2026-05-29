import _ from 'lodash';
import useLobbyStore from './lobby';

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

export default defineStore('lounge', {
  state: () => {
    return {
      tables: [] as number,
      games: [] as number,
      metadata: {} as GameInfo,
    }
  },
  getters: {
    tablesData() {
      const lobby = useLobbyStore();
      return _.map(this.tables, gameId => lobby.gameData(gameId));
    },
    gamesData() {
      const lobby = useLobbyStore();
      return _.map(this.games, gameId => lobby.gameData(gameId));
    },
  },
});
