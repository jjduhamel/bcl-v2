<script setup>
const { wallet } = await useWallet();
const { isAddress, isENSDomain, lookupENS } = await useEthUtils();

if (wallet.connected === false) {
  await navigateTo('/landing');
}

watch(() => wallet.connected, (isCon, wasCon) => {
  if (wasCon && !isCon) {
    navigateTo('/landing');
  }
});

const showChallengeModal = ref(false);

const opponent = ref(null);
const lookupAddress = ref(null);
async function lookupPlayer() {
  if (isAddress(lookupAddress.value)) {
    opponent.value = lookupAddress.value;
  } else if (isENSDomain(lookupAddress.value)) {
    opponent.value = await lookupENS(lookupAddress.value);
  } else {
    throw Error('Invalid input');
  }
  showChallengeModal.value = true;
}

function test(args) {
  console.log(args);
  console.log('color', args.startAsWhite ? 'w' : 'b');
  console.log('tpm', args.timePerMove);
  console.log('wager', args.wagerAmount);
  console.log('token', args.wagerToken);
}
</script>

<template lang='pug'>
section
  form(id='lookup-player', @submit.prevent)
    input(
      type='text',
      v-model='lookupAddress',
      placeholder='ETH Address/ENS Domain'
    )
    button(ref='submit', @click='lookupPlayer') Lookup

  div(id='player-lobby')
    div Challenges
    div Games
    div History

  client-only
    ChallengeModal(
      v-if='showChallengeModal'
      :walletConnectURI='walletConnectURI'
      :opponent='opponent'
      @submit='test'
      @close='() => showChallengeModal = false'
    )
</template>

<style lang='sass'>
#player-lobby
  @apply mx-1 my-2 text-lg
</style>
