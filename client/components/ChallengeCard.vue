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
    type: Number,
    required: true
  },
  wagerAmount: {
    type: [ Number, String ],
    required: true
  }
});
</script>

<template lang='pug'>
section
  Card(:indicator='isCurrentMove ? "green" : "orange"')
    div(class='mb-1 flex justify-center')
      img(
        v-if='isWhitePlayer'
        class='h-12'
        src='~assets/pieces/merida/wP.svg'
      )
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bP.svg'
      )

    div {{ truncAddress(opponent) }}
    div {{ formatEther(wagerAmount) }} ETH
</template>

<style lang='sass'>
</style>
