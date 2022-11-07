<script setup>
const props = defineProps({
  indicator: {
    type: [ null, String ],
    default: null
  }
});
</script>

<template lang='pug'>
section
  button(id='card' class='contents')
    div(class='w-24 h-24 mx-2 p-1 bordered flex flex-col')
      div(id='container' class='text-xs')
        slot
      div(v-if='indicator' id='indicator' class='p-1')
        div(id='circle' :style='{ "background-color": indicator }')

</template>

<style lang='sass'>
#card
  #indicator
    position: absolute

    #circle
      width: .5em
      height: .5em
      border-radius: 50%
</style>
