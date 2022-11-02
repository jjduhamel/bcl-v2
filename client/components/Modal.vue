<script setup>
import CloseIcon from '../assets/icons/bytesize/close.svg?raw';

const props = defineProps({
  title: String
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
          button(@click='$emit("close")')
            img(class='max-h-3' src='~assets/icons/bytesize/close.svg')
      slot
</template>

<style lang='sass'>
#shadow
  @apply fixed inset-0 z-10
  @apply bg-neutral-600/30

  #container
    @apply max-w-4xl flex justify-center

    #modal
      @apply mt-8 p-4
      @apply rounded-2xl
      @apply max-w-xs bg-white

      #head
        @apply mx-3

        button
          @apply contents
</style>
