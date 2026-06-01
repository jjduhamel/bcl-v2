<script setup>
import _ from 'lodash';
const { chains, changeNetwork } = await useWallet();
const emit = defineEmits([ 'close' ]);

async function doChangeNetwork(network) {
  console.log('Change network', network);
  const chain = _.find(chains, { network });
  if (!chain) throw Error('Invalid network');
  await changeNetwork(chain.id);
  emit('close');
}
</script>

<template lang='pug'>
Modal(title='Change Network' @close='emit("close")')
  div(id='switch-network-modal')
    div(class='text-center mb-2')
      slot
        div Please choose from the following list:
    div(v-if='false' class='grid grid-cols-1 text-center')
      button(disabled) Polygon
      button(disabled) Ethereum
    div(class='grid grid-cols-1 text-center')
      button(@click='() => doChangeNetwork("sepolia")') Sepolia Testnet
      button(@click='() => doChangeNetwork("foundry")') Localhost
</template>

<style lang='sass'>
#switch-network-modal
  div
    button
      @apply my-1 mx-8
</style>
