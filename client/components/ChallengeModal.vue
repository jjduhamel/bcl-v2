<script setup>
const emit = defineEmits([ 'submit' ]);

const props = defineProps({
  opponent: {
    type: String,
    default: '0x0000000000000000000000000000000000000000'
  },
  startAsWhite: {
    type: Boolean,
    default: true
  },
  timePerMove: {
    type: Number,
    default: 900
  },
  displayWager: {
    type: Number,
    default: 0
  }
});
</script>

<template lang='pug'>
Modal(title='New Challenge')
  ChallengeForm(
    id='new-challenge'
    v-bind='props'
    @submit='args => emit("send", args)'
  )
    button(type='submit' class='flex-1') Send
    div(class='w-2')
    button(type='button' class='flex-1' @click='$emit("close")') Cancel
</template>
