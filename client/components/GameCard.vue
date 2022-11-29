<script setup>
import humanizeDuration from 'humanize-duration';
import { formatEther } from 'ethers/lib/utils';
const { truncAddress } = useEthUtils();
const { GameState, GameOutcome } = await useChessEngine();

const props = defineProps({
  opponent: {
    type: String,
    required: true
  },
  state: {
    type: Number,
    default: 3
  },
  outcome: {
    type: Number,
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

const { state, outcome, isWhitePlayer, isCurrentMove } = toRefs(props);

const gameOver = computed(() => state.value == GameState.Finished);
const isWinner = computed(() => {
  if (!gameOver.value) return false;
  return isWhitePlayer.value ? (outcome.value == GameOutcome.WhiteWon)
                             : (outcome.value == GameOutcome.BlackWon);
});
const isLoser = computed(() => {
  if (!gameOver.value) return false;
  return isWhitePlayer.value ? (outcome.value == GameOutcome.BlackWon)
                             : (outcome.value == GameOutcome.WhiteWon);
});

const indicator = computed(() => {
  if (!gameOver.value) return isCurrentMove.value ? 'green' : 'orange';
  else if (isWinner.value) return 'green';
  else if (isLoser.value) return 'red';
  else return 'orange';
});

const displayTPM = computed(() => {
  return humanizeDuration(props.timePerMove*1000
                        , { largest: 1 });
});
</script>

<template lang='pug'>
section
  Card(:indicator='indicator')
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
    div(v-if='isWinner') Victory
    div(v-else-if='isLoser') Defeat
    div(v-else-if='gameOver') Finished
    div(v-else) {{ displayTPM }}
</template>
