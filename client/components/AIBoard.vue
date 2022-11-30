<script setup>
import _ from 'lodash';

const { chess, fen, legalMoves } = await useChessEngine();
const isCurrentMove = ref(true);

const chooseMove = async (from, to, capture) => {
  const move = chess.move({ from, to });
  fen.value = chess.fen();
  isCurrentMove.value = false;
  setTimeout(moveAI, 500);
}

const moveAI = () => {
  const moves = chess.moves({ verbose: true });
  const move = _.sample(moves);
  chess.move(move);
  fen.value = chess.fen();
  isCurrentMove.value = true;
}
</script>

<template>
  <ChessBoard
    v-bind='{ fen, legalMoves, isCurrentMove }'
    @moved='chooseMove'
  />
</template>
