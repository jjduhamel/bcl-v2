<script setup>
const {
  wallet,
  connectMetamask,
  connectWalletConnect,
  connectCoinbaseWallet,
} = await useWallet();

if (wallet.connected) {
  await navigateTo('/lounge');
}

const showWCModal = ref(false);
const walletConnectURI = ref(null);
const wcIsConnecting = ref(false);
async function startWalletConnect() {
  walletConnectURI.value = await connectWalletConnect();
  wcIsConnecting.value = true;
  showWCModal.value = true;
}

const showCBModal = ref(false);
const cbWalletUri = ref(null);
const cbIsConnecting = ref(false);
async function startCoinbaseWallet() {
  cbWalletUri.value = await connectCoinbaseWallet();
  cbIsConnecting.value = true;
  showCBModal.value = true;
}

watch(() => wallet.connected, (isCon, wasCon) => {
  if (!wasCon && isCon) {
    if (wcIsConnecting.value) {
      showWCModal.value = false;
      wcIsConnecting.value = false;
    }

    if (cbIsConnecting.value) {
      showCBModal.value = false;
      cbIsConnecting.value = false;
    }
    navigateTo('/lounge');
  }
});
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
        button(@click='startWalletConnect')
          img(src='@/assets/icons/walletconnect.png')
          div WalletConnect
        button(@click='startCoinbaseWallet')
          img(src='@/assets/icons/cbwallet-round.png')
          div Coinbase
    client-only
      QRModal(
        v-if='showWCModal'
        title='Wallet Connect'
        :uri='walletConnectURI'
        @close='() => showWCModal = false'
      )
        div Please scan this QR Code using a WalletConnect enabled wallet.

      QRModal(
        v-if='showCBModal'
        title='Coinbase Wallet'
        :uri='cbWalletUri'
        @close='() => showCBModal = false'
      )
        div Please scan this QR Code using Coinbase Wallet.
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
        @apply h-4

      div
        @apply flex-1
</style>
