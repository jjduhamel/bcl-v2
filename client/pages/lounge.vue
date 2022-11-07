<script setup>
import _ from 'lodash';
const { wallet } = await useWallet();
const { lobby } = await useLobby();
const { isAddress, isENSDomain, lookupENS } = await useEthUtils();

if (wallet.connected === false) {
  await navigateTo('/landing');
}

watch(() => wallet.connected, (isCon, wasCon) => {
  if (wasCon && !isCon) {
    navigateTo('/landing');
  }
});

const showChallengeModal = ref(false);
const searchText = ref(null);
const lookupAddress = ref(null);
async function createChallenge() {
  if (isAddress(searchText.value)) {
    lookupAddress.value = searchText.value;
  } else if (isENSDomain(searchText.value)) {
    lookupAddress.value = await lookupENS(searchText.value);
  } else {
    throw Error('Invalid input');
  }
  showChallengeModal.value = true;
}

const showPendingChallengeModal = ref(false);
const pendingChallenge = ref(null);
async function showPendingChallenge(gameId) {
  pendingChallenge.value = lobby.gameData(gameId);
  showPendingChallengeModal.value = true;
}

async function sendChallenge(args) {
  const { opponent
        , startAsWhite
        , timePerMove
        , wagerAmount
        , wagerToken } = args;
  await lobby.contract.challenge(opponent
                               , startAsWhite
                               , timePerMove
                               , wagerAmount
                             , { value: wagerAmount });
  const { CreatedChallenge } = lobby.contract.filters;
  const eventFilter = CreatedChallenge(null
                                     , wallet.address
                                     , opponent);
  lobby.contract.once(eventFilter, async id => {
    await lobby.newChallenge(id);
    showChallengeModal.value = false;
    console.log('Created challenge', id);
  });
}

async function acceptChallenge(gameId) {
  console.log('Accept challenge', gameId);
  const gameContract = lobby.chessEngine(gameId);
  await gameContract.acceptChallenge(gameId);
  const { GameStarted } = lobby.contract.filters;
  const eventFilter = GameStarted(gameId);
  lobby.contract.once(eventFilter, async () => {
    await lobby.newGame(gameId);
    showPendingChallenge.value = false;
    console.log('Accepted challenge', gameId);
  });
}

async function declineChallenge(gameId) {
  console.log('Decline challenge', gameId);
  const gameContract = lobby.chessEngine(gameId);
  await gameContract.declineChallenge(gameId);
  const { DeclinedChallenge } = lobby.contract.filters;
  const eventFilter = DeclinedChallenge(gameId);
  lobby.contract.once(eventFilter, () => {
    lobby.popChallenge(gameId);
    showPendingChallenge.value = false;
    console.log('Declined challenge', gameId);
  });
}

async function modifyChallenge(gameId, gameData) {
  console.log('Modify challenge', gameId, gameData);
  //await lobby.contract.modifyChallenge(gameId, FIXME);
  // TODO Wait for events
}
</script>

<template lang='pug'>
section
  form(id='lookup-player', @submit.prevent)
    input(
      type='text',
      v-model='searchText',
      placeholder='ETH Address/ENS Domain'
    )
    button(ref='submit', @click='createChallenge') Lookup

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

  client-only
    Modal(
      v-if='showChallengeModal'
      title='New Challenge'
      @close='() => showChallengeModal = false'
    )
      EditChallengeForm(
        id='new-challenge'
        :opponent='lookupAddress'
        @submit='sendChallenge'
        @cancel='() => showChallengeModal = false'
      )

    Modal(
      title='Pending Challenge'
      v-if='showPendingChallengeModal'
      @close='() => showPendingChallengeModal = false'
    )
      PendingChallengeForm(
        id='pending-challenge'
        v-bind='pendingChallenge'
        @accept='() => acceptChallenge(pendingChallenge.id)'
        @decline='() => declineChallenge(pendingChallenge.id)'
        @modify='data => modifyChallenge(pendingChallenge.id, data)'
      )
</template>

<style lang='sass'>
#player-lobby
  @apply mx-1 my-2 text-lg
</style>
