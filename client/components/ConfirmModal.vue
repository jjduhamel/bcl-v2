<script setup>
const emit = defineEmits([ 'confirm', 'close' ]);

const props = defineProps({
  loading: {
    type: Boolean,
    default: false
  }
});

const { loading } = toRefs(props);
</script>

<template lang='pug'>
Modal(@close='emit("close")')
  div(class='mb-4 text-center')
    slot
  div(id='form-controls')
    button(:disabled='loading' @click='emit("confirm")') Confirm
    button(:disabled='loading' @click='emit("close")') Cancel
</template>
