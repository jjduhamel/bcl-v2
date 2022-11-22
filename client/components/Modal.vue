<script setup>
//import CloseIcon from '../assets/icons/bytesize/close.svg?raw';

const emit = defineEmits([ 'close' ]);

const props = defineProps({
  title: {
    type: String,
    required: true
  }
})
</script>

<template lang='pug'>
div(id='shadow')
  div(id='container')
    div(id='modal' class='p-2 bordered')
      div(id='head' class='flex items-center')
        div(class='flex-1')
        div(class='text-xl') {{ props.title }}
        div(class='flex-1 flex items-center justify-end')
          button(@click='emit("close")')
            img(class='max-h-3' src='~assets/icons/bytesize/close.svg')
      div(id='modal-form' class='w-80')
        slot
</template>

<style lang='sass'>
#shadow
  @apply fixed inset-0 z-10
  @apply bg-neutral-600/30

  #container
    @apply max-w-4xl flex justify-center

    #modal
      @apply mt-8 p-3
      @apply rounded-2xl
      @apply bg-white

      #head
        @apply px-2 pb-1 border-b border-black

        button
          @apply contents

      #modal-form
        @apply px-2 mt-4

        #form-controls
          @apply mt-4 mb-2 flex justify-center

          button
            @apply w-20
</style>
