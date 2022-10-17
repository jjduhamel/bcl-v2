import _ from 'lodash';
import { Chess, SQUARES } from 'chess.js';

export default function() {
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

  return { engine, fen, legalMoves };
}
