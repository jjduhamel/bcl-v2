<script setup>
import _ from 'lodash';
import { formatEther, parseEther } from 'ethers/lib/utils';
const { truncAddress } = await useEthUtils();

const emit = defineEmits([ 'submit', 'cancel' ]);

const props = defineProps({
  opponent: {
    type: String,
    required: true
  },
  startAsWhite: {
    type: Boolean,
    default: true
  },
  timePerMove: {
    type: [ Number, String ],
    default: 900
  },
  wagerAmount: {
    type: [ Number, String ],
    default: 0
  }
});

const { opponent } = toRefs(props);

const startAsWhite = ref(props.startAsWhite);

const timeUnits = ref('minutes');
const timePerMove = ref(props.timePerMove);
const displayTPM = computed({
  get() {
    switch (timeUnits.value) {
      case 'minutes':
        return Math.round(timePerMove.value/60);
      case 'hours':
        return Math.round(timePerMove.value/3600);
      case 'days':
        return Math.round(timePerMove.value/3600/24);
      case 'weeks':
        return Math.round(timePerMove.value/3600/24/7);
    }
  },
  set(tpm) {
    switch (timeUnits.value) {
      case 'minutes':
        timePerMove.value = tpm*60;
        break;
      case 'hours':
        timePerMove.value = tpm*3600;
        break;
      case 'days':
        timePerMove.value = tpm*3600*24;
        break;
      case 'weeks':
        timePerMove.value = tpm*3600*24*7;
        break;
    }
  }
});

const wagerToken = ref('eth');
const wagerAmount = ref(props.wagerAmount);
const displayWager = computed({
  get() {
    return formatEther(wagerAmount.value, 3);
  },
  set(amount) {
    wagerAmount.value = parseEther(amount);
  }
});

const submit = () => emit('submit', _.mapValues({ opponent
                                                , startAsWhite
                                                , timePerMove
                                                , wagerAmount
                                                , wagerToken }
                                              , unref));
</script>

<template lang='pug'>
form(
  class='w-72'
  @submit.prevent='submit'
)
  div(id='opponent' class='mt-2 flex items-center')
    div(class='flex-1') Opponent:
    div(class='mx-4 flex-1 flex justify-end') {{ truncAddress(opponent, 4, 4) }}
  div(id='choose-color' class='mt-2 flex items-center')
    div(class='flex-1') Play As:
    div(class='mx-4 flex-1 flex justify-between')
      button(
        type='button'
        class='contents border-none'
        @click='() => startAsWhite = true'
      )
        img(
          class='h-12 border-2 border-transparent'
          :class='startAsWhite ? "bordered" : "unbordered"'
          src='~assets/pieces/merida/wP.svg')
      button(
        type='button'
        class='contents border-none'
        @click='() => startAsWhite = false'
      )
        img(
          class='h-12 border-2 border-transparent'
          :class='startAsWhite ? "unbordered" : "bordered"'
          src='~assets/pieces/merida/bP.svg')
  div(class='mt-2 flex items-center')
    div(class='flex-1') Time Per Move:
    div(class='flex-2 flex justify-end')
      input(class='w-16' v-model='displayTPM')
      select(class='w-20' v-model='timeUnits')
        option(value='minutes') Mins
        option(value='hours') Hours
        option(value='days') Days
        option(value='weeks') Weeks
  div(class='mt-2 flex items-center')
    div(class='flex-1') Wager:
    div(class='flex-1 flex justify-end')
      input(class='w-16' v-model='displayWager')
      select(class='w-20' v-model='wagerToken')
        option(value='eth') ETH
        option(value='dai') DAI
        option(value='usdt') USDT
        option(value='usdc') USDC
  div(id='controls' class='mt-4 mx-12 flex justify-center')
    button(type='submit' class='flex-1') Send
    div(class='w-2')
    button(type='button' class='flex-1' @click='emit("cancel")') Cancel
</template>
