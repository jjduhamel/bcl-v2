<template lang='pug'>
NuxtLayout(name='game')
  template(v-slot:board)
    AIBoard

  template(v-slot:info)
    div(id='caption')
      div Welcome!  Please connect your Ethereum Wallet using one of the following options.
</template>
