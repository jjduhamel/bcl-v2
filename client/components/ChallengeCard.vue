<script setup>
import humanizeDuration from 'humanize-duration';
import { formatEther } from 'ethers/lib/utils';
import { constants } from 'ethers';
const { truncAddress } = useEthUtils();

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
        src='~assets/pieces/merida/wR.svg'
      )
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bR.svg'
      )
    div(v-if='opponent != constants.AddressZero') {{ truncAddress(opponent) }}
    div(class='italic' v-else) Open Table
    div {{ formatEther(wagerAmount) }} ETH
</template>

<style lang='sass'>
</style>
