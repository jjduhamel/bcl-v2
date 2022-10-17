<template lang='pug'>
div(id='game')
  div(id='board')
    slot(name='board')
  div(id='info')
    slot(name='info')
</template>

<style lang='sass'>
html, body, #__nuxt, #app
  height: 100%

#game
  @apply flex

  #board
    @apply flex flex-grow

  #info
    @apply w-48 justify-end

    .bordered
      @apply p-2 border border-2 border-black rounded-xl

    #caption
      @apply text-center text-sm
      @extend .bordered
</style>
