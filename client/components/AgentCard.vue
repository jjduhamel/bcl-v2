<script setup>
import useEthUtils from '~/composables/useEthUtils';
import { ethers } from 'ethers';
const { truncAddress } = useEthUtils();

const props = defineProps({
  address: {
    type: String,
    required: true
  },
  nickname: {
    type: String,
    required: true
  },
  avatar: {
    type: String,
    default: ''
  },
  active: {
    type: Boolean,
    default: false
  },
  delegated: {
    type: Boolean,
    default: false
  }
});

// Generate a pseudo-random boolean from the address
const isWhiteAgent = computed(() => {
  const hash = ethers.utils.keccak256(props.address);
  const firstByte = parseInt(hash.slice(2, 4), 16);
  return firstByte % 2 === 0;
});

const indicator = computed(() => {
  if (!props.active) return 'red';
  if (!props.delegated) return 'orange';
  return 'green';
});
</script>

<template lang='pug'>
section
  Card(:indicator='indicator')
    div(class='mb-1 flex justify-center')
      img(v-if='avatar' class='h-12' :src='avatar')
      img(v-else-if='isWhiteAgent' class='h-12' src='~assets/pieces/merida/wB.svg')
      img(v-else class='h-12' src='~assets/pieces/merida/bB.svg')
    div {{ nickname }}
    div {{ truncAddress(address) }}
</template>
