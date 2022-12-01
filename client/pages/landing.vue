<script setup>
const {
  wallet,
  connectMetamask,
  connectWalletConnect,
  walletConnectURI
} = await useWallet();

if (wallet.connected) {
  await navigateTo('/lounge');
}

watch(walletConnectURI, (newURI, oldURI) => {
  if (!oldURI && newURI) {
    showWCModal.value = true;
  }
});

watch(() => wallet.connected, (isCon, wasCon) => {
  if (!wasCon && isCon) {
    showWCModal.value = false;
    navigateTo('/lounge');
  }
});

const showWCModal = ref(false);
</script>

<template lang='pug'>
NuxtLayout(name='game')
  template(v-slot:board)
    AIBoard

  template(v-slot:info)
    div(id='caption')
      div(class='text-lg font-bold') Welcome!
      div Please connect your Ethereum Wallet using one of the following:
      div(id='wallets')
        button(@click='connectMetamask')
          img(src='@/assets/icons/metamask-32px.png')
          div Metamask
        button(@click='connectWalletConnect')
          img(src='@/assets/icons/walletconnect.png')
          div WalletConnect
    client-only
      QRModal(
        title='WalletConnect'
        v-if='showWCModal'
        :uri='walletConnectURI'
        @close='() => showWCModal = false'
      )
</template>

<style lang='sass'>
#caption
  #wallets
    @apply mt-2
    @apply flex flex-col

    button
      @apply px-2 py-1 my-1 mx-3
      @apply flex-1 flex items-center justify-center
      @apply border border-2 border-black rounded-xl

      img
        @apply h-5

      div
        @apply flex-1
</style>
