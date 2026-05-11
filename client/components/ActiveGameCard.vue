<script setup>
import humanizeDuration from 'humanize-duration';
const { truncAddress } = useEthUtils();

const props = defineProps({
  opponent:      { type: String, required: true },
  isWhitePlayer: { type: Boolean, required: true },
  isCurrentMove: { type: Boolean, required: true },
  isInReview: { type: Boolean, default: false },
  timePerMove:   { type: Number, required: true },
});

const indicator = computed(() => props.isInReview ? 'red' : props.isCurrentMove ? 'green' : 'orange');
const displayTPM = computed(() => humanizeDuration(props.timePerMove*1000, { largest: 1 }));
</script>

<template lang='pug'>
section
  Card(:indicator='indicator')
    div(class='mb-1 flex justify-center')
      img(
        v-if='isWhitePlayer'
        class='h-12'
        src='~assets/pieces/merida/wN.svg'
      )
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bN.svg'
      )
    div(class='font-bold')
      div(v-if='isInReview') Under Review
      div(v-else) {{ displayTPM }}
    div {{ truncAddress(opponent) }}
</template>
