<script setup>
import _ from 'lodash';
import { constants } from 'ethers';

definePageMeta({
  layout: 'searchbar'
});

const { wallet } = await useWallet();

const {
  lobby,
  txPending,
  joinTable,
  acceptChallenge,
  declineChallenge,
  createTable,
  modifyChallenge,
  revokeTable,
  fetchOpenTables,
  fetchActiveGames
} = await useLobby();

Promise.all([
  fetchOpenTables(),
  fetchActiveGames()
]);

const openTable = ref(null);
const joinTableModal = ref(false);
const joinTableEditing = ref(false);
const joinTableRef = ref(null);
const createTableModal = ref(false);
const createTableRef = ref(null);

// The active wallet (or one of its agents) created the open table being viewed,
// so it shows Modify/Revoke instead of Join and the form is editable.
const isOwnTable = computed(() =>
  openTable.value && lobby.isOwnOpenTable(openTable.value.id)
);

function showCreateTable() {
  if (!lobby.isRegistered) throw Error('Register your wallet first (Register button, top bar).');
  createTableModal.value = true;
}

async function doCreateTable(args) {
  const { sender, startAsWhite, timePerMove, wagerAmount } = args;
  await createTable(sender, startAsWhite, timePerMove, wagerAmount);
  createTableModal.value = false;
}

function creatorOf(table) {
  if (lobby.isOpenTable(table.id)) {
    if (table.whitePlayer == constants.AddressZero) return table.blackPlayer;
    if (table.blackPlayer == constants.AddressZero) return table.whitePlayer;
  }
}

function playerAddr(table) {
  if (lobby.isOpenTable(table.id)) {
    if (lobby.isPlayer(table.id)) return creatorOf(table);
    return constants.AddressZero;
  } else {
    return lobby.player(table.id);
  }
}

function opponentAddr(table) {
  if (lobby.isOpenTable(table.id)) {
    if (lobby.isPlayer(table.id)) return constants.AddressZero;
    return creatorOf(table);
  } else {
    return lobby.opponent(table.id);
  }
}

// TODO: Sort these.  Should include open tables + challenges
const openGames = computed(() => [
  ..._.filter(lobby.challenges, c => lobby.isCurrentMove(c.id)),
  ..._.filter(lobby.openTables, c => !lobby.isOwnOpenTable(c.id)),
  ..._.filter(lobby.openTables, c => lobby.isOwnOpenTable(c.id))
]);

function statusColor(table) {
  if (lobby.isOpenTable(table.id)) {
    if (lobby.isOwnOpenTable(table.id)) return 'orange';
    return 'green';
  }
  else return 'orange';
}

function showJoinTable(table) {
  openTable.value = table;
  joinTableEditing.value = false;
  joinTableModal.value = true;
}

async function doJoinTable(sender) {
  if (!lobby.isRegistered) throw Error('Register your wallet first (Register button, top bar).');
  await joinTable(openTable.value.id, sender);
  joinTableModal.value = false;
}

async function doModifyTable(args) {
  const { sender, startAsWhite, timePerMove, wagerAmount } = args;
  await modifyChallenge(openTable.value.id, sender, startAsWhite, timePerMove, wagerAmount);
  joinTableEditing.value = false;
}

async function doRevokeTable() {
  await revokeTable(openTable.value.id);
  joinTableModal.value = false;
}

// A joiner has seated themselves and the turn is back with the creator to
// confirm: accept starts the game, decline drops the challenge.
async function doAcceptTable() {
  await acceptChallenge(openTable.value.id);
  joinTableModal.value = false;
}

async function doDeclineTable() {
  await declineChallenge(openTable.value.id);
  joinTableModal.value = false;
}
</script>

<template lang='pug'>
section
  div
    div(class='pb-1 border-b flex items-center justify-between')
      div Open Games
      button(
        v-if='wallet.connected'
        type='button'
        class='m-0 p-0 border-none group'
        title='Open Table'
        @click='showCreateTable'
      )
        img(class='h-4 px-4 opacity-30 group-hover:opacity-60' src='@/assets/icons/bytesize/plus.svg')
    div(v-if='openGames.length' class='my-2 flex')
      div(v-for='table in openGames' :key='table.id')
        ChallengeCard(
          v-bind='table'
          :opponent='opponentAddr(table)'
          :isCurrentMove='statusColor(table) == "green"'
          :isWhitePlayer='lobby.isPlayer(table.id)'
          @click='() => showJoinTable(table)'
        )
    div(v-else class='my-2 text-sm text-gray-500 italic') No open tables yet.

  div(class='my-4')
    div(class='pb-1 border-b') Active Games
    div(v-if='!lobby.activeGames.length' class='my-2 text-sm text-gray-500 italic') No active games to show
    div(v-else class='my-2 flex')
      div(v-for='game in lobby.activeGames' :key='game.id')
        ActiveGameCard(
          v-bind='{ ...game, opponent: game.currentMove, isCurrentMove: true }'
          :isWhitePlayer='game.currentMove == game.whitePlayer'
          @click='() => navigateTo("/game/"+game.id)'
        )

  client-only
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

    Modal(
      v-if='joinTableModal'
      title='Join Table'
      @close='() => joinTableModal = false'
    )
      ChallengeForm(
        ref='joinTableRef'
        id='join-table'
        :isEditing='joinTableEditing'
        :loading='txPending'
        :player='wallet.address'
        :opponent='opponentAddr(openTable)'
        :agents='lobby.agents'
        :timePerMove='openTable.timePerMove'
        :wagerAmount='openTable.wagerAmount'
        :isWhitePlayer='isOwnTable ? (openTable.whitePlayer === constants.AddressZero) : (openTable.whitePlayer !== constants.AddressZero)'
        @submit='doModifyTable'
      )
      div(id='form-controls' v-if='wallet.connected')
        template(v-if='isOwnTable && joinTableEditing')
          button(type='button' :disabled='txPending' @click='joinTableRef.submit()') Send
          button(type='button' :disabled='txPending' @click='() => joinTableEditing = false') Cancel
        template(v-else-if='isOwnTable')
          button(type='button' :disabled='txPending' @click='() => joinTableEditing = true') Modify
          button(type='button' :disabled='txPending' @click='doRevokeTable') Revoke
        template(v-else-if='lobby.isOpenTable(openTable.id)')
          button(
            type='button'
            :disabled='txPending || !wallet.connected'
            @click='doJoinTable(wallet.address)'
          ) Join
          button(type='button' @click='joinTableModal = false') Cancel
        template(v-else)
          button(type='button' :disabled='txPending || !wallet.connected' @click='doAcceptTable') Join
          button(type='button' :disabled='txPending' @click='doDeclineTable') Decline
</template>

<style lang='sass'>
section
  @apply mx-1 my-2 text-lg
</style>
