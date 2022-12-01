<script setup>
//import VueQR from 'vue-qr';
//import VueQR from 'vue3-qr-code-styling';
//import VueQR from '@diadal/vue3-qr-code-styling';
import VueQR from './vue3-qr-code-styling';

const props = defineProps({
  uri: {
    type: String,
    required: true
  }
});

const { uri } = toRefs(props);
</script>

<template lang='pug'>
Modal
  div(class='flex justify-center')
    VueQR(
      :width=512,
      :height=512,
      :data='uri',
      :dotsOptions='{ type: "extra-rounded", color: "black" }'
      :cornersSquareOptions='{ type: "extra-rounded" }'
      :cornersDotOptions='{ type: "dot" }'
    )
  div(class='my-1 text-center text-xs')
    slot
</template>
