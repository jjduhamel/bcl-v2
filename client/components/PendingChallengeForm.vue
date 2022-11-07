<script setup>
import _ from 'lodash';
import humanizeDuration from 'humanize-duration';
import { formatEther, parseEther } from 'ethers/lib/utils';
const { truncAddress } = await useEthUtils();

const emit = defineEmits([ 'accept', 'decline', 'modify' ]);

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

const { opponent, startAsWhite } = toRefs(props);
const modifyChallenge = ref(false);

const displayTPM = computed(() => {
  return humanizeDuration(props.timePerMove*1000
                        , { largest: 1 });
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
</script>

<template lang='pug'>
EditChallengeForm(
  v-if='modifyChallenge'
  v-bind='props'
  @submit='args => emit("modify", args)'
  @cancel='() => modifyChallenge = false'
)
div(v-else class='pr-4 w-72')
  div(id='opponent' class='mt-2 flex items-center')
    div(class='flex-1') Opponent:
    div(class='flex-1 flex justify-end') {{ truncAddress(opponent, 4, 4) }}
  div(id='choose-color' class='mt-2 flex items-center')
    div(class='flex-1') Play As:
    div(class='flex-1 flex justify-end')
      img(
        v-if='startAsWhite'
        class='h-12'
        src='~assets/pieces/merida/wP.svg')
      img(
        v-else
        class='h-12'
        src='~assets/pieces/merida/bP.svg')
  div(class='mt-2 flex items-center')
    div(class='flex-1') Time Per Move:
    div(class='flex-2 flex justify-end')
      div {{ displayTPM }}
  div(class='mt-2 flex items-center')
    div(class='flex-1') Wager:
    div(class='flex-1 flex justify-end')
      div() {{ displayWager }} ETH
  div(id='controls' class='mt-4 mx-12 flex justify-center')
    button(type='button' class='flex-1' @click='emit("accept")') Accept
    button(type='button' class='flex-1' @click='emit("decline")') Decline
    button(
      class='flex-1'
      @click='() => modifyChallenge = true'
    ) Modify
</template>
