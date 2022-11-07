<script setup>
import humanizeDuration from 'humanize-duration';
import { formatEther } from 'ethers/lib/utils';
const { truncAddress } = await useEthUtils();

const props = defineProps({
  opponent: {
    type: String,
    required: true
  },
  isWhitePlayer: {
    type: Boolean,
    required: true
  },
  isCurrentMove: {
    type: Boolean,
    required: true
  },
  timePerMove: {
    type: String,
    required: true
  },
  wagerAmount: {
    type: String,
    required: true
  }
});

const displayTPM = computed(() => {
  return humanizeDuration(props.timePerMove*1000
                        , { largest: 1 });
});
</script>

<template lang='pug'>
section
  Card(:indicator='isCurrentMove ? "green" : "orange"')
    div(class='mb-1 flex justify-center')
      img(
        v-if='isWhitePlayer'
        class='h-12'
        src='~assets/pieces/merida/wR.svg'
      )
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bR.svg'
      )

    div {{ truncAddress(opponent) }}
    div {{ displayTPM }}
</template>

<style lang='sass'>
</style>
