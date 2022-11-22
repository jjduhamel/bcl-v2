<template lang='pug'>
div(id='game')
  div(id='board')
    slot(name='board')
  div(id='info')
    slot(name='info')
</template>

<style lang='sass'>
#game
  @apply flex
  max-height: 27em

  #board
    @apply flex flex-grow

  #info
    @apply w-48 flex flex-col

    .bordered
      @apply p-2 border border-2 border-black rounded-xl

    #caption
      @apply flex-shrink text-center text-sm
      @extend .bordered

    #moves
      @apply flex-1 overflow-auto

    #controls
      @apply justify-end flex flex-col px-2

      button
        @apply flex-1
</style>
