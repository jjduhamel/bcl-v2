<script setup>
const { truncAddress } = useEthUtils();

const emit = defineEmits([ 'disconnect', 'changeNetwork' ]);

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
  div(id='account' class='py-0.5 flex items-center')
    img(class='h-4' src='~assets/icons/bytesize/user.svg')
    div(class='flex-1')
      div(v-if='connected') {{ truncAddress(address, 4) }}
      div(v-else) Disconnected
    button(
      title='Disconnect'
      v-if='connected'
      @click='emit("disconnect")'
    )
      img(class='h-4' src='~assets/icons/bytesize/lock.svg')
  div(id='network' class='py-0.5 flex items-center')
    img(class='h-4' src='~assets/icons/bytesize/link.svg')
    div(class='flex-1')
      div(v-if='connected') {{ network }}
      div(v-else) ---
    button(
      id='change-network'
      v-if='connected'
      title='Change Network'
      @click='emit("changeNetwork")'
    )
      img(class='h-4' src='~assets/icons/bytesize/ellipsis-horizontal.svg')
</template>

<style lang='sass'>
#wallet-status
  @apply text-sm

  div
    img
      @apply h-4 mb-0.5

    img:first-child
      @apply mr-1

    button
      all: unset
      cursor: pointer

  #network
    button
      img
        display: none

      &:disabled
        @apply text-gray-400 border-gray-400
        filter: invert(40%)

    &:hover
      button
        img
          display: block
</style>
