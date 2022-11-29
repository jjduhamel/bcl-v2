<script setup>
import _ from 'lodash';

definePageMeta({
  middleware: [ 'auth' ]
});

const { wallet } = await useWallet();

const {
  lobby,
  initPlayerLobby,
  txPending,
  sendChallenge,
  acceptChallenge,
  declineChallenge,
  modifyChallenge,
  createListeners,
  destroyListeners
} = await useLobby();

const { isAddress, isENSDomain, lookupENS } = useEthUtils();

const searchText = ref(null);
const lookupAddress = ref(null);
const newChallengeModal = ref(false);

async function newChallenge() {
  if (isAddress(searchText.value)) {
    lookupAddress.value = searchText.value;
  } else if (isENSDomain(searchText.value)) {
    lookupAddress.value = await lookupENS(searchText.value);
  } else {
    throw Error('Invalid input');
  }
  newChallengeModal.value = true;
}

function hideNewChallenge() {
  newChallengeModal.value = false
}

const pendingChallenge = ref(null);
const pendingChallengeModal = ref(false);

function showPendingChallenge(gameId) {
  pendingChallenge.value = lobby.gameData(gameId);
  pendingChallengeModal.value = true;
}

function hidePendingChallenge() {
  pendingChallenge.value = null;
  pendingChallengeModal.value = false;
}

async function doSendChallenge(args) {
  const { opponent
        , startAsWhite
        , timePerMove
        , wagerAmount
        , wagerToken } = args;
  await sendChallenge(opponent, startAsWhite, timePerMove, wagerAmount, wagerToken);
  newChallengeModal.value = false
}

async function doAcceptChallenge() {
  await acceptChallenge();
}

async function doDeclineChallenge() {
  await acceptChallenge();
}

async function doModifyChallenge(gameId, gameData) {
  const { startAsWhite, timePerMove, wagerAmount, wagerToken } = gameData;
  await modifyChallenge(gameId, startAsWhite, timePerMove, wagerAmount);
}

if (wallet.connected && !lobby.initialized) {
  initPlayerLobby();
}

createListeners();

onUnmounted(() => {
  destroyListeners();
});
</script>

<template lang='pug'>
section
  form(id='lookup-player', @submit.prevent)
    input(
      type='text',
      v-model='searchText',
      placeholder='ETH Address/ENS Domain'
    )
    button(ref='submit', @click='newChallenge') Lookup

  div(id='player-lobby')
    div Challenges
    div(class='my-2 flex')
      div(v-for='challenge in lobby.challenges')
        ChallengeCard(
          v-bind='challenge'
          @click='() => showPendingChallenge(challenge.id)'
        )

    div Games
    div(class='my-2 flex')
      div(v-for='game in lobby.games')
        GameCard(
          v-bind='game'
          @click='() => navigateTo("/game/"+game.id)'
        )

    div History
    div(class='my-2 flex')
      div(v-for='game in lobby.history')
        GameCard(
          v-bind='game'
          @click='() => navigateTo("/game/"+game.id)'
        )

  client-only
    Modal(
      v-if='newChallengeModal'
      title='New Challenge'
      @close='() => newChallengeModal = false'
    )
      EditChallengeForm(
        id='new-challenge'
        :loading='txPending'
        :opponent='lookupAddress'
        @submit='doSendChallenge'
        @cancel='() => newChallengeModal = false'
      )

    Modal(
      title='Pending Challenge'
      v-if='pendingChallengeModal'
      @close='hidePendingChallenge'
    )
      PendingChallengeForm(
        id='pending-challenge'
        :loading='txPending'
        v-bind='pendingChallenge'
        @accept='() => doAcceptChallenge(pendingChallenge.id).then(hidePendingChallenge)'
        @decline='() => doDeclineChallenge(pendingChallenge.id).then(hidePendingChallenge)'
        @modify='data => doModifyChallenge(pendingChallenge.id, data)'
      )
</template>

<style lang='sass'>
#player-lobby
  @apply mx-1 my-2 text-lg
</style>
