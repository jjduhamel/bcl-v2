<script setup>
import _ from 'lodash';

definePageMeta({
  middleware: [ 'auth' ],
  layout: 'searchbar'
});

const { wallet } = await useWallet();

const {
  lobby,
  txPending,
  acceptChallenge,
  declineChallenge,
  modifyChallenge,
  updateAgent,
  suspendAgent,
  resumeAgent,
  unregisterAgent,
  isAgent,
} = await useLobby();

const editAgent = ref(null);
const editAgentModal = ref(false);
const editAgentRef = ref(null);

function showEditAgent(agent) {
  editAgent.value = agent;
  editAgentModal.value = true;
}

async function doSuspendAgent() {
  await suspendAgent(editAgent.value.address);
  editAgentModal.value = false;
}

async function doResumeAgent() {
  await resumeAgent(editAgent.value.address);
  editAgentModal.value = false;
}

async function doUnregisterAgent() {
  await unregisterAgent(editAgent.value.address);
  editAgentModal.value = false;
}

const pendingChallenge = ref(null);
const pendingChallengeModal = ref(false);
const pendingChallengeEditing = ref(false);
const pendingChallengeRef = ref(null);

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
  pendingChallengeEditing.value = false;
}

async function doAcceptChallenge(gameId) {
  await acceptChallenge(gameId);
}

async function doDeclineChallenge(gameId) {
  await declineChallenge(gameId);
}

async function doModifyChallenge(gameId, gameData) {
  const { sender, startAsWhite, timePerMove, wagerAmount } = gameData;
  await modifyChallenge(gameId, sender, startAsWhite, timePerMove, wagerAmount);
}
</script>

<template lang='pug'>
section
  div(class='my-4')
    div(class='mb-4')
      div(class='pb-2 border-b') My Agents
      div(class='my-2 flex')
        div(class='mx-2 text-sm text-gray-500 italic'
            v-if='lobby.agents.length==0'
        ) No agents to show
        div(v-for='agent in lobby.agents' :key='agent.address')
          AgentCard(v-bind='agent' @click='() => showEditAgent(agent)')

    div(class='my-4')
      div(class='pb-2 border-b') Pending Challenges
      div(class='my-2 flex')
        div(class='mx-2 text-sm text-gray-500 italic'
            v-if='lobby.challenges.length==0'
        ) No pending challenges to show
        div(v-for='challenge in lobby.challenges')
          ChallengeCard(
            v-bind='challenge'
            @click='() => showPendingChallenge(challenge.id)'
          )

    div(class='my-4')
      div(class='pb-2 border-b') Active Games
      div(class='my-2 flex')
        div(class='mx-2 text-sm text-gray-500 italic'
            v-if='lobby.games.length==0'
        ) No active games to show
        div(v-else v-for='game in lobby.games')
          ActiveGameCard(
            v-bind='game'
            @click='() => navigateTo("/game/"+game.id)'
          )

    div(class='my-4') 
      div(class='pb-2 border-b') Game History
      div(class='my-2 flex')
        div(class='mx-2 text-sm text-gray-500 italic'
            v-if='lobby.history.length==0'
        ) No finished games to show
        div(v-else v-for='game in lobby.history')
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
      ProfileForm(
        ref='editAgentRef'
        :profile='editAgent'
        :editable='true'
        :loading='txPending'
        @update='({ nickname, avatar }) => updateAgent(editAgent.address, nickname, avatar)'
      )
      div(id='form-controls')
        template(v-if='editAgentRef?.editing')
          button(type='button' :disabled='txPending || !editAgentRef?.canSubmit' @click='editAgentRef.save()') Save
          button(type='button' :disabled='txPending' @click='editAgentRef.cancelEdit()') Cancel
        template(v-else)
          button(
            type='button'
            :disabled='txPending'
            @click='editAgent.active ? doSuspendAgent() : doResumeAgent()'
          ) {{ editAgent.active ? 'Suspend' : 'Resume' }}
          button(type='button' :disabled='txPending' @click='doUnregisterAgent') Unregister

    Modal(
      title='Pending Challenge'
      v-if='pendingChallengeModal'
      @close='hidePendingChallenge'
    )
      ChallengeForm(
        ref='pendingChallengeRef'
        id='pending-challenge'
        :isEditing='pendingChallengeEditing'
        :loading='txPending'
        v-bind='pendingChallenge'
        @submit='data => doModifyChallenge(pendingChallenge.id, data)'
      )
      div(id='form-controls')
        template(v-if='pendingChallengeEditing')
          button(type='button' :disabled='txPending' @click='pendingChallengeRef.submit()') Send
          button(type='button' :disabled='txPending' @click='() => pendingChallengeEditing = false') Cancel
        template(v-else)
          button(
            v-if='pendingChallenge.isCurrentMove'
            type='button'
            :disabled='txPending'
            @click='() => doAcceptChallenge(pendingChallenge.id).then(hidePendingChallenge)'
          ) Accept
          button(
            v-else
            type='button'
            :disabled='txPending'
            @click='() => pendingChallengeEditing = true'
          ) Modify
          button(
            type='button'
            :disabled='txPending'
            @click='() => doDeclineChallenge(pendingChallenge.id).then(hidePendingChallenge)'
          ) Decline
</template>
