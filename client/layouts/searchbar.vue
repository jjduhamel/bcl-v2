<script setup>
import _ from 'lodash';

const { wallet, connectMetamask } = await useWallet();

const {
  lobby,
  initPlayerLobby,
  txPending,
  sendChallenge,
  createTable,
  registerPlayer,
  registerAgent,
  fetchProfile,
  createListeners,
  destroyListeners
} = await useLobby();

const { isAddress, isENSDomain, lookupENS } = useEthUtils();

const searchText = ref(null);
const lookupAddress = ref(null);
const lookupIsAgent = ref(false);
const viewedProfile = ref(null);
const viewProfileModal = ref(false);
const newChallengeModal = ref(false);
const createTableModal = ref(false);
const registerPlayerModal = ref(false);
const registerAgentModal = ref(false);
const newChallengeRef = ref(null);
const createTableRef = ref(null);
const registerPlayerRef = ref(null);
const registerAgentRef = ref(null);

async function doRegisterPlayer(args) {
  const { username, avatar } = args;
  await registerPlayer(username, avatar);
  registerPlayerModal.value = false;
  await initPlayerLobby();
}

const isSelfLookup = computed(() => {
  if (!lookupAddress.value) return false;
  const mine = [ wallet.address, ..._.map(lobby.agents, 'address') ];
  return mine.some(a => a?.toLowerCase() === lookupAddress.value.toLowerCase());
});

const viewedIsRegistered = computed(() => {
  const p = viewedProfile.value;
  if (!p) return false;
  return !!p.owner || (p.createdAt ?? 0) > 0;
});

async function lookupProfile() {
  if (isAddress(searchText.value)) {
    lookupAddress.value = searchText.value;
  } else if (isENSDomain(searchText.value)) {
    lookupAddress.value = await lookupENS(searchText.value);
  } else {
    throw Error('Invalid input');
  }
  viewedProfile.value = await fetchProfile(lookupAddress.value);
  viewProfileModal.value = true;
}

function startChallenge() {
  // Lobby reads revert Unregistered() until the wallet has a profile; surface
  // the registration modal first so the user can opt in inline.
  if (!lobby.isRegistered) {
    registerPlayerModal.value = true;
    return;
  }
  if (isSelfLookup.value) throw Error('Cannot challenge yourself or your own agent');
  lookupIsAgent.value = !!viewedProfile.value?.owner;
  viewProfileModal.value = false;
  newChallengeModal.value = true;
}

function showRegisterModal() {
  if (!lobby.isRegistered) {
    registerPlayerModal.value = true;
    return;
  }
  if (!isAddress(searchText.value)) throw Error('Invalid input');
  registerAgentModal.value = true;
}

function showCreateTableModal() {
  if (!lobby.isRegistered) {
    registerPlayerModal.value = true;
    return;
  }
  createTableModal.value = true;
}

async function doRegisterAgent(args) {
  const { robot, nickname, avatar } = args;
  await registerAgent(robot, nickname, avatar);
  registerAgentModal.value = false;
}

async function doSendChallenge(args) {
  const { sender, opponent, startAsWhite, timePerMove, wagerAmount } = args;
  await sendChallenge(sender, opponent, startAsWhite, timePerMove, wagerAmount);
  newChallengeModal.value = false;
}

async function doCreateTable(args) {
  const { sender, startAsWhite, timePerMove, wagerAmount } = args;
  await createTable(sender, startAsWhite, timePerMove, wagerAmount);
  createTableModal.value = false;
}

if (wallet.connected && !lobby.initialized) {
  initPlayerLobby();
}

// MetaMask account switches keep the page mounted but useLobby's signer is
// captured at mount-time. The lobby store would also stay keyed to the old
// wallet, mis-firing the registration gate. Hard-reload — MetaMask's own
// recommendation — is the cleanest reset.
watch(() => wallet.address, (newAddr, oldAddr) => {
  if (!newAddr || !oldAddr || newAddr === oldAddr) return;
  window.location.reload();
});

// Re-register whenever the agent set changes; immediate covers the wallet-only
// case before agents finish loading, and picks up register/unregister mid-session.
watch(() => _.map(lobby.agents, 'address').join(','), () => {
  if (!wallet.connected) return;  // event filters key on wallet.address
  destroyListeners();
  createListeners();
}, { immediate: true });

onUnmounted(() => {
  destroyListeners();
});
</script>

<template lang='pug'>
NuxtLayout(name='default')
  div(id='player-search' class='flex justify-between')
    form(@submit.prevent, class='flex-1 flex items-center gap-1')
      input(
        class='flex-1'
        type='text',
        v-model='searchText',
        placeholder='ETH Address/ENS Domain'
      )
      button(@click='lookupProfile') Lookup
    div(class='flex items-center gap-1')
      template(v-if='wallet.connected')
        button(type='button', @click='showCreateTableModal') Open Table
        button(type='button', @click='showRegisterModal') {{ lobby.isRegistered ? 'Register Agent' : 'Register' }}
      button(v-else type='button' class='flex items-center gap-2' @click='connectMetamask')
        img(class='h-5 w-4 object-contain' src='@/assets/icons/metamask-32px.png')
        span Connect

  slot

  client-only
    Modal(
      v-if='registerPlayerModal'
      title='Register Player'
      @close='() => registerPlayerModal = false'
    )
      ProfileForm(
        ref='registerPlayerRef'
        id='register-player'
        :isEditing='true'
        :loading='txPending'
        :profile='lobby.playerProfile'
        :address='wallet.address'
        @register='doRegisterPlayer'
      )
      div(id='form-controls')
        button(
          type='button'
          :disabled='txPending || !wallet.connected || !registerPlayerRef?.canSubmit'
          @click='registerPlayerRef.save()'
        ) Register
        button(type='button' :disabled='txPending' @click='() => registerPlayerModal = false') Cancel

    Modal(
      v-if='viewProfileModal'
      title='Profile'
      @close='() => viewProfileModal = false'
    )
      ProfileForm(:profile='viewedProfile')
      div(id='form-controls')
        button(
          type='button'
          :disabled='!viewedIsRegistered || isSelfLookup || !wallet.connected'
          @click='startChallenge'
        ) Challenge

    Modal(
      v-if='registerAgentModal'
      title='Register Agent'
      @close='() => registerAgentModal = false'
    )
      ProfileForm(
        ref='registerAgentRef'
        id='register-agent'
        :isEditing='true'
        :loading='txPending'
        :profile='{ owner: wallet.address }'
        :address='searchText'
        @register='doRegisterAgent'
      )
      div(id='form-controls')
        button(
          type='button'
          :disabled='txPending || !wallet.connected || !registerAgentRef?.canSubmit'
          @click='registerAgentRef.save()'
        ) Register
        button(type='button' :disabled='txPending' @click='() => registerAgentModal = false') Cancel

    Modal(
      v-if='newChallengeModal'
      title='New Challenge'
      @close='() => newChallengeModal = false'
    )
      ChallengeForm(
        ref='newChallengeRef'
        id='new-challenge'
        :isEditing='true'
        :loading='txPending'
        :player='wallet.address'
        :agents='lobby.agents'
        :opponent='lookupAddress'
        :opponent-is-agent='lookupIsAgent'
        @submit='doSendChallenge'
      )
      div(id='form-controls')
        button(type='button' :disabled='txPending || !wallet.connected' @click='newChallengeRef.submit()') Send
        button(type='button' :disabled='txPending' @click='() => newChallengeModal = false') Cancel

    Modal(
      v-if='createTableModal'
      title='Create Open Table'
      @close='() => createTableModal = false'
    )
      ChallengeForm(
        ref='createTableRef'
        id='create-table'
        :isEditing='true'
        :loading='txPending'
        :player='wallet.address'
        :agents='lobby.agents'
        @submit='doCreateTable'
      )
      div(id='form-controls')
        button(type='button' :disabled='txPending || !wallet.connected' @click='createTableRef.submit()') Send
        button(type='button' :disabled='txPending' @click='() => createTableModal = false') Cancel
</template>
