<script setup>
const {
  wallet,
  currentNetwork,
  currentBalance,
  disconnectWallet
} = await useWallet();
</script>

<template lang='pug'>
div(id='app')
  div(id='body')
    div(id='sidebar')
      div(id='container')
        div(id='brand')
          div The Blockchain
          div Chess Lounge
        div(id='wallet')
          WalletStatusPane(
            :connected='wallet.connected'
            :address='wallet.address'
            :network='currentNetwork'
            :balance='currentBalance'
            @disconnect='disconnectWallet'
          )
        div(id='navigation')
          NuxtLink(to='/lounge') Lounge
          NuxtLink(to='/marketplace') Market
          NuxtLink(to='/about') About

    div(id='content')
      slot

  div(id='footer')
    div This site is protected from bots by algoz.xyz
    div(id='links')
      a(href='https://twitter.com/TheChessLounge')
        img(class='w-3' src='~assets/icons/bytesize/twitter.svg')
      a(href='https://github.com/jjduhamel/bcl-v2')
        img(class='w-3' src='~assets/icons/bytesize/github.svg')
</template>

<style lang='sass'>
html, body, #__nuxt, #app
  height: 100%

#app
  @apply px-2 max-w-4xl flex flex-col
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

  button:disabled
    @apply text-gray-400 border-gray-400
    filter: invert(40%)

  button:disabled.unbordered
    @extend .unbordered

  #body
    @apply mt-2 p-2 flex flex-grow

    #sidebar
      @apply min-w-fit

      #container
        @apply p-2 border border-2 border-black rounded-2xl

      #brand
        @apply mx-1 mt-2 text-center text-2xl font-bold

      #wallet
        @apply p-1 mx-1 my-2
        @extend .bordered

        #row
          @apply px-0.5 flex justify-end

      #navigation
        @apply mx-2 flex flex-col

        a
          @apply m-1 p-0.5 flex-1 text-center
          @extend .bordered

    #content
      @apply ml-3 mt-2 w-full

  #footer
    @apply p-0.5 flex-shrink flex text-xs
    @apply border-solid border-t border-black

    #links
      @apply flex-1 flex items-center justify-end

      a
        @apply pr-1
</style>
