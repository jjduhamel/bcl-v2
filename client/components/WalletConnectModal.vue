<script setup>
//import VueQR from 'vue-qr';
//import VueQR from 'vue3-qr-code-styling';
//import VueQR from '@diadal/vue3-qr-code-styling';
import VueQR from './vue3-qr-code-styling';

const props = defineProps({
  walletConnectURI: {
    type: String,
    required: true
  }
});

const { walletConnectURI } = toRefs(props);
</script>

<template lang='pug'>
Modal(title='WalletConnect')
  div(class='my-2 flex justify-center')
    VueQR(
      :width=256,
      :height=256,
      :data='walletConnectURI',
      image='assets/icons/wc-qrimg.png',
      :imageOptions='{ hideBackgroundDots: false }'
      :dotsOptions='{ type: "extra-rounded", color: "black" }'
      :cornersSquareOptions='{ type: "extra-rounded" }'
      :cornersDotOptions='{ type: "dot" }'
    )
  div(class='text-center text-sm') Please scan this QR code using a WalletConnect enabled wallet.
</template>
