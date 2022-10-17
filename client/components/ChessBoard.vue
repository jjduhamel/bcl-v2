<script setup>
import { Chessground } from 'chessground';
import '../assets/styles/chessground.css';
import '../assets/styles/theme.css';

const props = defineProps({
  fen: {
    type: String,
    required: true
  },
  legalMoves: {
    type: Object,
    required: true
  },
  // Events
  didMove: {
    type: Function,
    default(from, to) { console.log('Moved', from, to) }
  }
})

const { fen, legalMoves } = toRefs(props);

// Reference to draw the board in the DOM
const board = ref(null);
const chessground = ref(null);

// Draw chessboard when page mounts
onMounted(() => {
  console.log('Chessboard mounted');
  chessground.value = new Chessground(unref(board), {
    animation: { enabled: false },
    fen: unref(fen),
    movable: {
      free: false,
      dests: unref(legalMoves),
      showDests: true,
      events: {
        after: props.didMove
      }
    }
  });
});

// Redraw board when the FEN changes
watch(fen, (newFen) => {
  chessground.value.set({
    fen: newFen,
    movable: {
      free: false,
      dests: unref(legalMoves),
      showDests: true,
    }
  });
});
</script>

<template lang='pug'>
div(id='chessboard' class='ml-4 mb-2 blue merida')
  div(ref='board' class='cg-wrap')
</template>

<style lang='sass'>
#chessboard
  @apply mb-4
</style>
