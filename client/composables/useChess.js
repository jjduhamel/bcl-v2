import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';

export default async function(gameId) {
  const engine = new Chess();

  const fen = ref(engine.fen());

  const legalMoves = computed(() => {
    fen.value;            // Make reactive to FEN updates
    const out = new Map();
    _.forEach(SQUARES, sq => {
      const ms = engine.moves({ square: sq, verbose: true });
      if (ms.length > 0) out.set(sq, _.map(ms, 'to'));
    });
    return out;
  });

  if (!gameId) {
    return { engine, fen, legalMoves };
  }

  console.log('Initialize game', gameId);
  const { wallet } = await useWallet();
  const { lobby } = await useLobby();
  const gameData = lobby.gameData(gameId);
  //const gameData = reactive(lobby.gameData(gameId));

  const isWhitePlayer = computed(() => {
    return (wallet.address == gameData.whitePlayer);
  });

  const isBlackPlayer = computed(() => {
    return (wallet.address == gameData.blackPlayer);
  });

  const isPlayer = computed(() => {
    return isWhitePlayer.value || isBlackPlayer.value;
  });

  const opponent = computed(() => {
    if (!isPlayer) throw Error('Not a player');
    const { whitePlayer, blackPlayer } = gameData;
    return isWhitePlayer.value ? blackPlayer : whitePlayer;
  });

  const color = computed(() => {
    if (!isPlayer) throw Error('Not a player');
    return isWhitePlayer.value ? 'w' : 'b';
  });

  const opponentColor = computed(() => {
    if (!isPlayer) throw Error('Not a player');
    return isWhitePlayer.value ? 'b' : 'w';
  });

  const isCurrentMove = computed(() => {
    return gameData.currentMove == wallet.address;
  });

  const isOpponentsMove = computed(() => {
    return gameData.currentMove == opponent.value;
  });

  return {
    engine,
    fen,
    legalMoves,
    opponent
  };
}
