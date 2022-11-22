<script setup>
import _ from 'lodash';

const { engine, fen, legalMoves } = await useChess();

const chooseMove = async (from, to, capture) => {
  const move = engine.move({ from, to });
  fen.value = engine.fen();
  if (!move) throw Error('Illegal move', from, '->', to);
  setTimeout(moveAI, 500);
}

const moveAI = () => {
  const moves = engine.moves({ verbose: true });
  const move = _.sample(moves);
  engine.move(move);
  fen.value = engine.fen();
}
</script>

<template>
  <ChessBoard
    v-bind='{ fen, legalMoves }'
    @moved='chooseMove'
  />
</template>
