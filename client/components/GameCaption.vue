<script setup>
import humanizeDuration from 'humanize-duration';
import { formatEther } from 'ethers/lib/utils';
const { truncAddress } = useEthUtils();

const props = defineProps({
  gameOver:            { type: Boolean, default: false },
  isWinner:            { type: Boolean, default: false },
  isLoser:             { type: Boolean, default: false },
  isDisputed:          { type: Boolean, default: false },
  inCheck:             { type: Boolean, default: false },
  inCheckmate:         { type: Boolean, default: false },
  opponentInCheckmate: { type: Boolean, default: false },
  isCurrentMove:       { type: Boolean, default: false },
  didChooseMove:       { type: Boolean, default: false },
  didSendMove:         { type: Boolean, default: false },
  timerExpired:        { type: Boolean, default: false },
  timeUntilExpiry:     { type: Number, required: true },
  wagerAmount:         { type: [ String, Number ], default: '0' },
  opponent:            { type: String, required: true },
});

const { timeUntilExpiry } = toRefs(props);

// Built once at module-eval time; the computed below just calls it.
const humanize = humanizeDuration.humanizer({
  language: 'shortEn',
  languages: {
    shortEn: {
      y: () => 'year',
      mo: () => 'months',
      w: () => 'weeks',
      d: () => 'days',
      h: () => 'hours',
      m: () => 'mins',
      s: () => 'secs'
    }
  }
});

const displayTimer = computed(() => {
  if (timeUntilExpiry.value > 3600) {         // > 1 hour
    return humanize(timeUntilExpiry.value*1000, { largest: 2, delimiter: ' ' });
  } else {                                    // < 1 hour
    const mins = Math.floor(timeUntilExpiry.value / 60);
    const secs = timeUntilExpiry.value % 60;
    return `${mins}`.padStart(2, 0) + ':' + `${secs}`.padStart(2, 0);
  }
});
</script>

<template lang='pug'>
div(id='caption')
  div(v-if='gameOver' class='text-lg font-bold')
    div(v-if='isWinner') Victory!
    div(v-else-if='isLoser') Defeat
    div(v-else) Draw
  div(v-else-if='isDisputed' class='text-lg font-bold') Under Review
  div(v-else class='text-lg font-bold')
    div(v-if='inCheckmate || opponentInCheckmate') Checkmate!
    div(v-else-if='inCheck') Check!
    div(v-else-if='didSendMove') Pending...
    div(v-else-if='didChooseMove') Submit Move
    div(v-else-if='isCurrentMove') Your Move
    div(v-else) Opponent's Move
  div(class='text-lg')
    div(v-if='gameOver || isDisputed') -- : --
    div(v-else-if='!timerExpired') {{ displayTimer }}
    div(v-else) Timer Expired
  div(class='mx-2')
    div(id='opponent' class='py-0.5 flex justify-between items-center')
      img(class='h-4' src='~assets/icons/bytesize/user.svg')
      div {{ truncAddress(opponent, 4) }}
    div(id='wager' class='py-0.5 flex justify-between items-center')
      img(class='h-4' src='~assets/icons/trophy.svg')
      div {{ formatEther(wagerAmount) }} ETH
</template>
