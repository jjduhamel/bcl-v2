<script setup>
const { wallet } = await useWallet();
const { truncAddress } = await useEthUtils();

const displayAddr = computed(() => {
  return wallet.connected ? truncAddress(wallet.address) : '---';
});

const displayNetwork = computed(() => {
  return wallet.connected ? wallet.network : '---';
});
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
          div(id='item')
            div Address
            div {{ displayAddr }}
          div(id='item')
            div Network
            div {{ displayNetwork }}
        div(id='navigation')
          NuxtLink(to='/lounge') Lounge
          NuxtLink(to='/marketplace') Market
          NuxtLink(to='/about') About

    div(id='content')
      slot

  div(id='footer')
    div This site is protected from bots by algoz.xyz
</template>

<style lang='sass'>
html, body, #__nuxt, #app
  height: 100%

#app
  @apply px-2 max-w-4xl flex flex-col

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

        #item
          @apply px-0.5 flex justify-end
          @apply border-b border-black

          &:last-child
            @apply border-b-0

          div
            @apply flex-1 flex items-end

          :first-child
            @apply flex-shrink

          :nth-child(2)
            @apply text-sm justify-end

      #navigation
        @apply mx-2 flex flex-col

        a
          @apply m-1 p-0.5 flex-1 text-center
          @extend .bordered

    #content
      @apply ml-3 mt-2 w-full

  #footer
    @apply p-0.5 flex-shrink text-xs
    @apply border-solid border-t border-black
</style>
