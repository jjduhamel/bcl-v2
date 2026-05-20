<script setup>
defineProps({
  didChooseMove:       { type: Boolean, default: false },
  didSendMove:         { type: Boolean, default: false },
  didWithdrawWinnings: { type: Boolean, default: false },
  gameOver:            { type: Boolean, default: false },
  isDisputed:          { type: Boolean, default: false },
  isWinner:            { type: Boolean, default: false },
  isCurrentMove:       { type: Boolean, default: false },
  inDrawOffer:         { type: Boolean, default: false },
  checkmatePending:    { type: Boolean, default: false },
  playerTimeExpired:   { type: Boolean, default: false },
  opponentTimeExpired: { type: Boolean, default: false },
  canCaptureKing:      { type: Boolean, default: false },
});

defineEmits([
  'undo', 'offer-draw', 'resign', 'resign-now',
  'submit', 'claim-victory', 'claim-king-capture', 'claim-winnings'
]);
</script>

<template lang='pug'>
div(id='controls' class='pb-2')
  div(id='controlbar' class='p-2 flex justify-between')
    button(
      title='Undo Move'
      class='unbordered'
      :disabled='!didChooseMove || didSendMove || inDrawOffer'
      @click='$emit("undo")'
    )
      img(class='w-6' src='~assets/icons/bytesize/trash.svg')
    button(
      title='Offer Draw'
      class='unbordered'
      @click='$emit("offer-draw")'
      :disabled='gameOver || isDisputed || inDrawOffer || !isCurrentMove || didChooseMove'
    )
      img(class='w-6' src='~assets/icons/bytesize/flag.svg')
    button(
      title='Resign'
      class='unbordered'
      @click='$emit("resign")'
      :disabled='gameOver || inDrawOffer'
    )
      img(class='w-6' src='~assets/icons/bytesize/ban.svg')

  button(
    v-if='gameOver && isWinner'
    title='Claim Winnings'
    :disabled='didWithdrawWinnings'
    @click='$emit("claim-winnings")'
  ) Claim Winnings
  button(
    v-else-if='(!didChooseMove && checkmatePending) || playerTimeExpired'
    title='Resign'
    @click='$emit("resign-now")'
  ) Resign
  button(
    v-else-if='canCaptureKing'
    title='Claim Victory'
    @click='$emit("claim-king-capture")'
  ) Claim Victory
  button(
    v-else-if='opponentTimeExpired'
    title='Claim Victory'
    @click='$emit("claim-victory")'
  ) Claim Victory
  button(
    v-else
    title='Submit Move'
    :disabled='!didChooseMove || didSendMove || isDisputed || inDrawOffer'
    @click='$emit("submit")'
  ) Submit
</template>
