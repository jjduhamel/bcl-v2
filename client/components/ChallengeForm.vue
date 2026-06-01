<script setup>
import _ from 'lodash';
import humanizeDuration from 'humanize-duration';
import { formatEther, parseEther } from 'ethers/lib/utils';
import userIcon from '~/assets/icons/bytesize/user.svg';
import robotIcon from '~/assets/icons/robot.svg';
const { truncAddress } = useEthUtils();

const emit = defineEmits([ 'submit' ]);

const props = defineProps({
  loading:         { type: Boolean, default: false },
  isEditing:       { type: Boolean, default: false },
  player:          { type: String,  default: null },
  agents:          { type: Array,   default: () => [] },
  opponent:        { type: String,  default: '' },
  isWhitePlayer:   { type: Boolean, default: true },
  playerIsAgent:   { type: Boolean, default: false },
  opponentIsAgent: { type: Boolean, default: false },
  timePerMove:     { type: [ Number, String ], default: 900 },
  wagerAmount:     { type: [ Number, String ], default: 0 }
});

const { opponent } = toRefs(props);

const senderOptions = computed(() => [
  { address: props.player, nickname: 'Myself' },
  ...props.agents
]);
const sender = ref(props.player);
const senderIsAgent = computed(() =>
  sender.value === props.player ? props.playerIsAgent
                                : _.some(props.agents, { address: sender.value })
);

const startAsWhite = ref(props.isWhitePlayer);

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
const fixedTPM = computed(() => {
  const [ value, ...unit ] = humanizeDuration(timePerMove.value*1000
                                            , { largest: 1 }).split(' ');
  return { value, unit: _.upperFirst(unit.join(' ')) };
});

const wagerAmount = ref(props.wagerAmount);
const displayWager = computed({
  get() {
    return formatEther(wagerAmount.value, 3);
  },
  set(amount) {
    wagerAmount.value = parseEther(amount);
  }
});

const wagerToken = ref('ETH');

const submit = () => emit('submit', _.mapValues({ sender
                                                , opponent
                                                , startAsWhite
                                                , timePerMove
                                                , wagerAmount
                                                , wagerToken }
                                              , unref));

// When the parent flips isEditing back off (Cancel/revert), discard the user's
// in-progress edits by reseating from the props.
watch(() => props.isEditing, (now, prev) => {
  if (prev && !now) {
    sender.value = props.player;
    startAsWhite.value = props.isWhitePlayer;
    timePerMove.value = props.timePerMove;
    wagerAmount.value = props.wagerAmount;
    wagerToken.value = 'ETH';
  }
});

// Action buttons live in the parent; expose `submit` so the parent's Send
// button can trigger the emit without owning all the field state.
defineExpose({ submit });
</script>

<template lang='pug'>
form(@submit.prevent='submit')
  div(class='my-4 pb-3 flex justify-center items-center text-sm border-b')
    div(class='flex-1 flex flex-col justify-center items-center gap-3')
      img(class='h-12' src='~assets/pieces/merida/wN.svg' v-if='startAsWhite')
      img(class='h-12' src='~assets/pieces/merida/bN.svg' v-else)
      div(class='flex items-start gap-2')
        img(class='h-4' :src='senderIsAgent ? robotIcon : userIcon')
        div {{ truncAddress(sender, 4) }}
    div(class='text-lg') vs.
    div(class='flex-1 flex flex-col justify-center items-center gap-2')
      img(class='h-12' src='~assets/pieces/merida/bN.svg' v-if='startAsWhite')
      img(class='h-12' src='~assets/pieces/merida/wN.svg' v-else)
      div(v-if='opponent' class='flex items-start gap-2')
        img(class='h-4' :src='opponentIsAgent ? robotIcon : userIcon')
        div {{ truncAddress(opponent, 4) }}
      div(v-else class='text-sm text-gray-400 italic') Open
  div(class='text-xl font-bold') Match Summary:
  div(v-if='isEditing && agents.length' class='my-4 flex items-center')
    div(class='basis-2/5') I'm playing as:
    div(class='basis-3/5 flex justify-start')
      div(class='flex-1 relative flex')
        img(
          class='h-4 absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none'
          :src='senderIsAgent ? robotIcon : userIcon'
        )
        select(class='flex-1' style='padding-left: 2rem' v-model='sender')
          option(v-for='a in senderOptions' :key='a.address' :value='a.address') {{ a.nickname || truncAddress(a.address, 4, 4) }}
  div(id='choose-color' class='my-4 flex items-center')
    div(class='basis-2/5') I'll start as:
    div(class='basis-3/5 flex justify-start gap-1')
      template(v-if='isEditing')
        button(
          type='button'
          class='contents border-none'
          @click='() => startAsWhite = true'
        )
          div(
            class='flex-1 mx-1 px-2 py-1 flex justify-center items-center gap-1'
            :class='startAsWhite ? "bordered" : "unbordered"'
          )
            img(class='h-5' src='~assets/pieces/merida/wP.svg')
            div White
        button(
          type='button'
          class='contents border-none'
          @click='() => startAsWhite = false'
        )
          div(
            class='flex-1 mx-1 px-2 py-1 flex justify-center items-center gap-1 border-2 border-transparent'
            :class='!startAsWhite ? "bordered" : "unbordered"'
          )
            img(class='h-5' src='~assets/pieces/merida/bP.svg')
            div Black
      div(v-else class='flex-1 flex items-center justify-center gap-1')
        div(class='flex-1 flex justify-end')
          img(v-if='startAsWhite' class='h-5' src='~assets/pieces/merida/wP.svg')
          img(v-else class='h-5' src='~assets/pieces/merida/bP.svg')
        div(class='flex-1 flex justify-center gap-2')
          div {{ startAsWhite ? 'White' : 'Black' }}
  div(class='my-4 flex items-center')
    div(class='basis-2/5') Time per move:
    div(class='basis-3/5 flex justify-start')
      template(v-if='isEditing')
        input(class='flex-1 w-16' v-model='displayTPM')
        select(class='w-20' v-model='timeUnits')
          option(value='minutes') Mins
          option(value='hours') Hours
          option(value='days') Days
          option(value='weeks') Weeks
      div(class='flex-1 flex gap-2' v-else)
        div(class='flex-1 text-end') {{ fixedTPM.value }}
        div(class='flex-1 text-center') {{ fixedTPM.unit }}
  div(class='my-4 flex items-center')
    div(class='basis-2/5') Let's wager:
    div(class='basis-3/5 flex justify-start')
      template(v-if='isEditing')
        input(class='flex-1 w-16' v-model='displayWager')
        select(class='w-20' v-model='wagerToken')
          option(value='ETH') ETH
          option(value='USDC' disabled) USDC
          option(value='USDT' disabled) USDT
          option(value='NITE' disabled) NITE
      div(class='flex-1 flex gap-2' v-else)
        div(class='flex-1 text-end') {{ displayWager }}
        div(class='flex-1 text-center') {{ wagerToken }}
</template>
