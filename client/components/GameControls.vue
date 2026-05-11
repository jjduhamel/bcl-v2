<script setup>
defineProps({
  didChooseMove:       { type: Boolean, default: false },
  didSendMove:         { type: Boolean, default: false },
  didWithdrawWinnings: { type: Boolean, default: false },
  gameOver:            { type: Boolean, default: false },
  isDisputed:          { type: Boolean, default: false },
  isWinner:            { type: Boolean, default: false },
  checkmatePending:    { type: Boolean, default: false },
  playerTimeExpired:   { type: Boolean, default: false },
  opponentTimeExpired: { type: Boolean, default: false },
});

defineEmits([
  'undo', 'offer-draw', 'resign', 'resign-now',
  'submit', 'claim-victory', 'claim-winnings'
]);
</script>

<template lang='pug'>
div(id='controls' class='pb-2')
  div(id='controlbar' class='p-2 flex justify-between')
    button(
      title='Undo Move'
      class='unbordered'
      :disabled='!didChooseMove || didSendMove'
      @click='$emit("undo")'
    )
      img(class='w-6' src='~assets/icons/bytesize/trash.svg')
    button(
      title='Offer Draw'
      class='unbordered'
      @click='$emit("offer-draw")'
      disabled
    )
      img(class='w-6' src='~assets/icons/bytesize/flag.svg')
    button(
      title='Resign'
      class='unbordered'
      @click='$emit("resign")'
      :disabled='gameOver'
    )
      img(class='w-6' src='~assets/icons/bytesize/ban.svg')

  button(
    title='Claim Winnings'
    v-if='gameOver && isWinner'
    :disabled='didWithdrawWinnings'
    @click='$emit("claim-winnings")'
  ) Claim Winnings
  button(
    title='Resign'
    v-else-if='checkmatePending || playerTimeExpired'
    @click='$emit("resign-now")'
  ) Resign
  button(
    title='Claim Victory'
    v-else-if='opponentTimeExpired'
    @click='$emit("claim-victory")'
  ) Claim Victory
  button(
    title='Submit Move'
    v-else-if='!gameOver'
    :disabled='!didChooseMove || didSendMove || isDisputed'
    @click='$emit("submit")'
  ) Submit
</template>
