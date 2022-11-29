<script setup>
const { truncAddress } = useEthUtils();

const emit = defineEmits([ 'disconnect' ]);

const props = defineProps({
  connected: {
    type: Boolean,
    default: false
  },
  address: {
    type: String,
    required: true
  },
  network: {
    type: String,
    required: true
  },
  balance: {
    type: String,
    required: true
  },
});
</script>

<template lang='pug'>
div(id='wallet-status')
  div(id='row')
    div(id='current-player')
      img(class='h-4' src='~assets/icons/bytesize/user.svg')
      div(v-if='connected') {{ truncAddress(address) }}
      div(v-else) Disconnected
    div(id='wallet-controls')
      button(
        title='Disconnect'
        :disabled='!connected'
        @click='emit("disconnect")'
      )
        img(class='h-4' src='~assets/icons/bytesize/lock.svg')
  div(id='row')
    div(id='current-network')
      img(class='h-4' src='~assets/icons/bytesize/link.svg')
      div(v-if='connected') {{ network }}
      div(v-else) ---
    div(id='wallet-balance')
      div {{ balance }}
</template>

<style lang='sass'>
#wallet-status
  @apply text-sm

  #row
    @apply py-0.5 flex items-center

    img
      @apply mr-1

    button
      all: unset
      cursor: pointer

      img
        @apply m-0 ml-1

      &:disabled
        @apply text-gray-400 border-gray-400
        filter: invert(40%)

    div
      @apply flex

    #current-player, #current-network
      @apply flex-shrink

    #wallet-controls, #wallet-balance
      @apply flex-1 justify-end
</style>
