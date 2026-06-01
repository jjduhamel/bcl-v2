<script setup>
const {
  wallet,
  currentNetwork,
  currentBalance,
  disconnectWallet,
  changeNetwork,
} = await useWallet();

const showChangeNetworkModal = ref(false);
</script>

<template lang='pug'>
div(id='app')
  div(id='body')
    div(id='sidebar')
      div(id='container')
        div(id='brand')
          img(class='h-16 mx-auto mb-2' src='@/assets/pieces/merida/bQ.svg')
          div(class='text-md font-thin italic tracking-widest') The Blockchain
          div(class='text-3xl font-bold') Chess Lounge
          div(class='mt-4 border-t-2 border-black w-16 mx-auto')
        div(id='wallet')
          WalletStatusPane(
            :connected='wallet.connected'
            :address='wallet.address'
            :network='currentNetwork'
            :balance='currentBalance'
            @disconnect='disconnectWallet'
            @changeNetwork='() => showChangeNetworkModal = true'
          )
        div(id='navigation')
          NuxtLink(to='/lounge')
            img(src='@/assets/icons/pawn.svg')
            div Lounge
          NuxtLink(to='/lobby' v-if='wallet.connected')
            img(src='@/assets/icons/bytesize/star.svg')
            div Lobby
          NuxtLink(to='/about')
            img(src='@/assets/icons/bytesize/info.svg')
            div Rules
          NuxtLink(to='/agents')
            img(src='@/assets/icons/robot.svg')
            div Tutorial

    div(id='content')
      slot

  div(id='footer')
    div Built for Robots and Humans
    div(id='links')
      a(href='https://twitter.com/TheChessLounge')
        img(class='w-3' src='~assets/icons/bytesize/twitter.svg')
      a(href='https://github.com/jjduhamel/bcl-v2')
        img(class='w-3' src='~assets/icons/bytesize/github.svg')

  div(id='modals')
    SwitchNetworkModal(
      v-if='showChangeNetworkModal'
      @close='() => showChangeNetworkModal = false'
    )
</template>

<style lang='sass'>
html, body, #__nuxt, #app
  height: 100%
  background-color: #fbfaf6

#app
  @apply px-2 max-w-full flex flex-col
  font-family: "Times New Roman", Times, serif

  /*
   * Default Look
   */

  .bordered
    @apply border border-2 border-black rounded-lg

  .unbordered
    @apply border border-2 border-transparent

  input, select, button
    //box-sizing: border-box
    @apply h-8 px-2 py-1 mx-1 my-0
    @apply bg-transparent

    @extend .bordered
    &.border-none
      @apply m-0 p-0 h-auto

    &:focus
      outline: 1px solid black

    &:disabled
      @apply text-gray-400 border-gray-400
      filter: invert(40%)

  button
    @apply items-center justify-center
    @apply leading-none

    &:disabled.unbordered
      @extend .unbordered

  #body
    @apply mt-2 p-2 flex flex-grow min-h-0 overflow-y-auto

    #sidebar
      @apply min-w-fit flex flex-col

      #container
        @apply p-2 border border-2 border-black rounded-2xl flex flex-col

      #brand
        @apply my-4 mx-4 text-center

      #wallet
        @apply px-2 py-1 mx-1 my-2
        @extend .bordered

      #navigation
        @apply my-4 mx-2 flex-1 flex flex-col

        a
          @apply m-1 px-2 py-1 flex items-center
          @extend .bordered

          img
            @apply h-4 w-4 object-contain

          div
            @apply flex-1 text-center

    #content
      @apply ml-4 mb-8 w-full

  #footer
    @apply p-0.5 flex-shrink flex text-xs
    @apply border-solid border-t border-black

    #links
      @apply flex-1 flex items-center justify-end

      a
        @apply pr-1
</style>
