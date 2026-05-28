<script>
// In a plain <script> so defineProps (hoisted) can reference it for a default.
const GameOutcome = { Undecided: 0, WhiteWon: 1, BlackWon: 2, Draw: 3 };
</script>

<script setup>
import humanizeDuration from 'humanize-duration';
import { formatEther } from 'ethers/lib/utils';
const { truncAddress } = useEthUtils();

const props = defineProps({
  gameOutcome:         { type: Number, default: GameOutcome.Undecided },
  isWhitePlayer:       { type: Boolean, default: false },
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
  opponent:            { type: String, default: '' },
  isSpectator:         { type: Boolean, default: false },
  whitePlayer:         { type: String, default: '' },
  blackPlayer:         { type: String, default: '' },
  currentMove:         { type: String, default: '' },
  statusText:          { type: String, default: '' },
});

const { timeUntilExpiry } = toRefs(props);

const gameOver = computed(() => props.gameOutcome !== GameOutcome.Undecided);
const whiteWon = computed(() => props.gameOutcome === GameOutcome.WhiteWon);
const blackWon = computed(() => props.gameOutcome === GameOutcome.BlackWon);
const isDraw = computed(() => props.gameOutcome === GameOutcome.Draw);
const isWinner = computed(() => !props.isSpectator
  && ((props.isWhitePlayer && whiteWon.value) || (!props.isWhitePlayer && blackWon.value)));
const isLoser = computed(() => !props.isSpectator
  && gameOver.value && !isDraw.value && !isWinner.value);

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
    template(v-if='isSpectator')
      div(v-if='whiteWon') White Won
      div(v-else-if='blackWon') Black Won
      div(v-else) Draw
    div(v-else-if='isWinner' class='text-green-600') You Won!
    div(v-else-if='isLoser' class='text-red-600') You Lost
    div(v-else) Draw
  div(v-else-if='isDisputed' class='text-lg font-bold') Under Review
  div(v-else class='text-lg font-bold')
    div(v-if='isSpectator') {{ currentMove === whitePlayer ? "White's Move" : "Black's Move" }}
    div(v-else-if='inCheckmate' class='text-red-600') Checkmate!
    div(v-else-if='opponentInCheckmate' class='text-green-600') Checkmate!
    div(v-else-if='inCheck') Check!
    div(v-else-if='didSendMove') Pending...
    div(v-else-if='didChooseMove') Submit Move
    div(v-else-if='isCurrentMove') Your Move
    div(v-else) Opponent's Move
  div(class='text-lg')
    div(v-if='gameOver || isDisputed') -- : --
    div(v-else-if='!timerExpired') {{ displayTimer }}
    div(v-else class='text-red-600') Timer Expired
  div(class='mx-2')
    div(id='opponent' class='py-0.5 flex justify-between items-center')
      img(class='h-4' src='~assets/icons/bytesize/user.svg')
      div {{ truncAddress(opponent, 4) }}
    div(id='wager' class='py-0.5 flex justify-between items-center')
      img(class='h-4' src='~assets/icons/trophy.svg')
      div {{ formatEther(wagerAmount) }} ETH
</template>
