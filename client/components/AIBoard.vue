<script setup>
import _ from 'lodash';

const { chess, fen, legalMoves } = await useChessEngine();

const chooseMove = async (from, to, capture) => {
  const move = chess.move({ from, to });
  fen.value = chess.fen();
  if (!move) throw Error('Illegal move', from, '->', to);
  setTimeout(moveAI, 500);
}

const moveAI = () => {
  const moves = chess.moves({ verbose: true });
  const move = _.sample(moves);
  chess.move(move);
  fen.value = chess.fen();
}
</script>

<template>
  <ChessBoard
    v-bind='{ fen, legalMoves }'
    @moved='chooseMove'
  />
</template>
