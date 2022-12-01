<script setup>
const emit = defineEmits([ 'click' ]);
</script>

<template lang='pug'>
Modal(title='Switch Network')
  div(id='switch-network-modal')
    div(class='text-center mb-2')
      slot
        div Please choose from the following list:
    div(class='grid grid-cols-2 text-center')
      button(disabled) Ethereum
      button(disabled) Polygon
      button(@click='emit("click", 5)') Goerli Testnet
      button(@click='emit("click", 80001)') Mumbai Testnet
</template>

<style lang='sass'>
#switch-network-modal
  div
    button
      @apply m-1
</style>
