<script setup>
import { Chessground } from 'chessground';
import '../assets/styles/chessground.css';
import '../assets/styles/theme.css';

const emit = defineEmits([ 'moved' ]);

const props = defineProps({
  fen: {
    type: String,
    required: true
  },
  legalMoves: {
    type: Object,
    required: true
  },
  isWhitePlayer: {
    type: Boolean,
    default: true
  },
  isCurrentMove: {
    type: Boolean,
    default: true
  }
})

const { fen, legalMoves, isCurrentMove } = toRefs(props);
const playerColor = props.isWhitePlayer ? 'white' : 'black';
const opponentColor = props.isWhitePlayer ? 'black' : 'white';

// Reference to draw the board in the DOM
const board = ref(null);
const chessground = ref(null);

function reloadBoard() {
  chessground.value.set({
    fen: unref(fen),
    turnColor: isCurrentMove.value ? playerColor : opponentColor,
    movable: {
      dests: unref(legalMoves)
    }
  });
}

// Draw chessboard when page mounts
onMounted(() => {
  console.log('Chessboard mounted');
  chessground.value = new Chessground(unref(board), {
    animation: { enabled: false },
    orientation: playerColor,
    movable: {
      free: false,
      color: playerColor,
      showDests: true,
    },
    events: {
      move: (from, to, capture) => emit('moved', from, to, capture)
    }
  });

  reloadBoard();

});

watch(isCurrentMove, reloadBoard);
watch(fen, reloadBoard);
</script>

<template lang='pug'>
div(id='chessboard' class='mb-2 blue merida')
  div(ref='board' class='cg-wrap')
</template>

<style lang='sass'>
#chessboard
  @apply mb-4
</style>
