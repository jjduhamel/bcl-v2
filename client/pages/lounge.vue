<script setup>
import { constants } from 'ethers';

definePageMeta({
  layout: 'searchbar'
});

const { wallet } = await useWallet();

const {
  lobby,
  lounge,
  txPending,
  joinTable,
  modifyChallenge,
  revokeTable,
  fetchOpenTables,
  fetchActiveGames
} = await useLobby();

await Promise.all([
  fetchOpenTables(),
  fetchActiveGames()
]);

// On open tables exactly one seat is filled (the creator). Resolve them so the
// card shows their address instead of address(0).
function creatorOf(table) {
  return table.whitePlayer === constants.AddressZero ? table.blackPlayer
                                                     : table.whitePlayer;
}

const openTable = ref(null);
const joinTableModal = ref(false);
const joinTableEditing = ref(false);
const joinTableRef = ref(null);

// True when the active wallet owns the seat that created the table — either as
// itself or one of its agents (lobby.controls covers both).
const isOwnTable = computed(() =>
  openTable.value && lobby.controls(creatorOf(openTable.value))
);

function showJoinTable(table) {
  openTable.value = table;
  joinTableEditing.value = false;
  joinTableModal.value = true;
}

async function doJoinTable(args) {
  if (!lobby.isRegistered) throw Error('Register your wallet first (Register button, top bar).');
  const { sender, startAsWhite } = args;
  await joinTable(openTable.value.id, sender, startAsWhite);
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
</script>

<template lang='pug'>
section
  div(class='my-4')
    div(class='pb-2 border-b') Open Games
    div(v-if='lounge.tables.length' class='my-2 flex')
      div(v-for='table in lounge.tablesData' :key='table.id')
        ChallengeCard(
          v-bind='table'
          :isCurrentMove='wallet.address !== creatorOf(table)'
          :opponent='creatorOf(table)'
          :isWhitePlayer='creatorOf(table) == table.whitePlayer ? isOwnTable : !isOwnTable'
          @click='() => showJoinTable(table)'
        )
    div(v-else class='my-2 text-sm text-gray-500 italic') No open tables yet.

  div(class='my-4')
    div(class='pb-2 border-b') Active Games
    div(v-if='lounge.games.length' class='my-2 flex')
      div(v-for='game in lounge.gamesData' :key='game.id')
        ActiveGameCard(
          v-bind='{ ...game, opponent: game.currentMove, isCurrentMove: true }'
          :isWhitePlayer='game.currentMove == game.whitePlayer'
          @click='() => navigateTo("/game/"+game.id)'
        )
    div(v-else class='my-2 text-sm text-gray-500 italic') No active games to show

  client-only
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
        :player='isOwnTable ? creatorOf(openTable) : wallet.address'
        :opponent='isOwnTable ? "" : creatorOf(openTable)'
        :agents='lobby.agents'
        :timePerMove='openTable.timePerMove'
        :wagerAmount='openTable.wagerAmount'
        :isWhitePlayer='isOwnTable ? (openTable.whitePlayer !== constants.AddressZero) : (openTable.whitePlayer === constants.AddressZero)'
        @submit='doModifyTable'
      )
      div(id='form-controls')
        template(v-if='!isOwnTable')
          button(
            type='button'
            :disabled='txPending || !wallet.connected'
            @click='doJoinTable({ sender: wallet.address, startAsWhite: openTable.whitePlayer === constants.AddressZero })'
          ) Join
          button(type='button' @click='joinTableModal = false') Cancel
        template(v-else-if='joinTableEditing')
          button(type='button' :disabled='txPending' @click='joinTableRef.submit()') Send
          button(type='button' :disabled='txPending' @click='() => joinTableEditing = false') Cancel
        template(v-else)
          button(type='button' :disabled='txPending' @click='() => joinTableEditing = true') Modify
          button(type='button' :disabled='txPending' @click='doRevokeTable') Revoke
</template>

<style lang='sass'>
section
  @apply mx-1 my-2 text-lg
</style>
