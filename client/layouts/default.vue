<template lang='pug'>
div(id='app')
  div(id='body')
    div(id='sidebar')
      div(class='bordered rounded-2xl')
        div(id='brand')
          div The Blockchain
          div Chess Lounge
        div(id='navigation')
          NuxtLink(to='/') Lounge
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

  #body
    @apply mt-2 p-2 flex flex-grow

    #sidebar
      @apply min-w-fit

      .bordered
        @apply p-2 border border-2 border-black

      #brand
        @apply my-2 text-center text-2xl

      #navigation
        @apply mx-2 flex flex-col

        a
          @apply m-1 p-0.5 flex-1 text-center rounded-xl
          @extend .bordered

    #content
      @apply ml-3 mt-2 w-full

  #footer
    @apply p-0.5 flex-shrink text-xs
    @apply border-solid border-t border-black
</style>
