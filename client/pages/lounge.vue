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
  registerAgent,
  updateAgent,
  suspendAgent,
  unregisterAgent,
  isAgent,
  createListeners,
  destroyListeners
} = await useLobby();

const { isAddress, isENSDomain, lookupENS } = useEthUtils();

const searchText = ref(null);
const lookupAddress = ref(null);
const lookupIsAgent = ref(false);
const newChallengeModal = ref(false);

async function newChallenge() {
  if (isAddress(searchText.value)) {
    lookupAddress.value = searchText.value;
  } else if (isENSDomain(searchText.value)) {
    lookupAddress.value = await lookupENS(searchText.value);
  } else {
    throw Error('Invalid input');
  }
  const mine = [ wallet.address, ..._.map(lobby.agents, 'address') ];
  if (mine.some(a => a?.toLowerCase() === lookupAddress.value.toLowerCase())) {
    throw Error('Cannot challenge yourself or your own agent');
  }
  lookupIsAgent.value = await isAgent(lookupAddress.value);
  newChallengeModal.value = true;
}

function hideNewChallenge() {
  newChallengeModal.value = false
}

const registerAgentModal = ref(false);

function showRegisterAgent() {
  if (!isAddress(searchText.value)) throw Error('Invalid input');
  registerAgentModal.value = true;
}

async function doRegisterAgent(args) {
  const { robot, nickname, avatar } = args;
  await registerAgent(robot, nickname, avatar);
  registerAgentModal.value = false;
}

const editAgent = ref(null);
const editAgentModal = ref(false);

function showEditAgent(agent) {
  editAgent.value = agent;
  editAgentModal.value = true;
}

async function doSuspendAgent() {
  await suspendAgent(editAgent.value.address);
  editAgentModal.value = false;
}

async function doUnregisterAgent() {
  await unregisterAgent(editAgent.value.address);
  editAgentModal.value = false;
}


const pendingChallenge = ref(null);
const pendingChallengeModal = ref(false);

async function showPendingChallenge(gameId) {
  const data = lobby.gameData(gameId);
  const [ playerIsAgent, opponentIsAgent ] = await Promise.all([
    isAgent(data.player),
    isAgent(data.opponent)
  ]);
  pendingChallenge.value = { ...data, playerIsAgent, opponentIsAgent };
  pendingChallengeModal.value = true;
}

function hidePendingChallenge() {
  pendingChallenge.value = null;
  pendingChallengeModal.value = false;
}

async function doSendChallenge(args) {
  const { sender, opponent, startAsWhite, timePerMove, wagerAmount } = args;
  await sendChallenge(sender, opponent, startAsWhite, timePerMove, wagerAmount);
  newChallengeModal.value = false;
}

async function doAcceptChallenge(gameId) {
  await acceptChallenge(gameId);
}

async function doDeclineChallenge(gameId) {
  await declineChallenge(gameId);
}

async function doModifyChallenge(gameId, gameData) {
  const { startAsWhite, timePerMove, wagerAmount } = gameData;
  await modifyChallenge(gameId, startAsWhite, timePerMove, wagerAmount);
}

if (wallet.connected && !lobby.initialized) {
  initPlayerLobby();
}

// Re-register whenever the agent set changes; immediate covers the wallet-only
// case before agents finish loading, and picks up register/unregister mid-session.
watch(() => _.map(lobby.agents, 'address').join(','), () => {
  destroyListeners();
  createListeners();
}, { immediate: true });

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
    button(type='button', @click='showRegisterAgent') Register Agent

  div(id='player-lobby')
    div(class='mb-4 mt-2')
      div My Agents
      div(class='my-2 flex')
        div(v-for='agent in lobby.agents' :key='agent.address')
          AgentCard(v-bind='agent' @click='() => showEditAgent(agent)')

    div(class='my-4')
      div Pending Challenges
      div(class='my-2 flex')
        div(v-for='challenge in lobby.challenges')
          ChallengeCard(
            v-bind='challenge'
            @click='() => showPendingChallenge(challenge.id)'
          )

    div(class='my-4')
      div Active Games
      div(class='my-2 flex')
        div(v-for='game in lobby.games')
          ActiveGameCard(
            v-bind='game'
            @click='() => navigateTo("/game/"+game.id)'
          )

    div(class='my-4') Game History
    div(class='my-2 flex')
      div(v-for='game in lobby.history')
        GameOverCard(
          v-bind='game'
          @click='() => navigateTo("/game/"+game.id)'
        )

  client-only
    Modal(
      v-if='editAgentModal'
      title='Agent Profile'
      @close='() => editAgentModal = false'
    )
      AgentProfileForm(
        v-bind='editAgent'
        :loading='txPending'
        @update='({ nickname, avatar }) => updateAgent(editAgent.address, nickname, avatar)'
        @suspend='doSuspendAgent'
        @unregister='doUnregisterAgent'
      )

    Modal(
      v-if='registerAgentModal'
      title='Register Agent'
      @close='() => registerAgentModal = false'
    )
      AgentProfileForm(
        id='register-agent'
        :isEditing='true'
        :loading='txPending'
        :owner='wallet.address'
        :address='searchText'
        @register='doRegisterAgent'
        @cancel='() => registerAgentModal = false'
      )

    Modal(
      v-if='newChallengeModal'
      title='New Challenge'
      @close='() => newChallengeModal = false'
    )
      ChallengeForm(
        id='new-challenge'
        :isEditing='true'
        :loading='txPending'
        :player='wallet.address'
        :agents='lobby.agents'
        :opponent='lookupAddress'
        :opponent-is-agent='lookupIsAgent'
        @submit='doSendChallenge'
        @cancel='() => newChallengeModal = false'
      )

    Modal(
      title='Pending Challenge'
      v-if='pendingChallengeModal'
      @close='hidePendingChallenge'
    )
      ChallengeForm(
        id='pending-challenge'
        :isEditing='false'
        :loading='txPending'
        v-bind='pendingChallenge'
        @accept='() => doAcceptChallenge(pendingChallenge.id).then(hidePendingChallenge)'
        @decline='() => doDeclineChallenge(pendingChallenge.id).then(hidePendingChallenge)'
        @submit='data => doModifyChallenge(pendingChallenge.id, data)'
      )
</template>

<style lang='sass'>
#player-lobby
  @apply mx-1 my-2 text-lg
</style>
