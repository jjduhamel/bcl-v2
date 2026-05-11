<script setup>
const { truncAddress } = useEthUtils();
const { GameOutcome } = await useChessEngine();

const props = defineProps({
  opponent:      { type: String, required: true },
  isWhitePlayer: { type: Boolean, required: true },
  outcome:       { type: Number, required: true },
});

const { outcome, isWhitePlayer } = toRefs(props);

const isWinner = computed(() => isWhitePlayer.value
  ? outcome.value == GameOutcome.WhiteWon
  : outcome.value == GameOutcome.BlackWon);
const isLoser = computed(() => isWhitePlayer.value
  ? outcome.value == GameOutcome.BlackWon
  : outcome.value == GameOutcome.WhiteWon);

const indicator = computed(() => {
  if (isWinner.value) return 'green';
  if (isLoser.value) return 'red';
  return 'orange';
});
</script>

<template lang='pug'>
section
  Card(:indicator='indicator')
    div(class='mb-1 flex justify-center')
      img(
        v-if='isWhitePlayer'
        class='h-12'
        src='~assets/pieces/merida/wK.svg'
      )
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bK.svg'
      )
    div(class='font-bold')
      div(v-if='isWinner') Victory
      div(v-else-if='isLoser') Defeat
      div(v-else) Draw
    div {{ truncAddress(opponent) }}
</template>
