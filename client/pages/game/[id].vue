<script setup>
import _ from 'lodash';
import humanizeDuration from 'humanize-duration';

const { params } = useRoute();
const gameId = params.id;
const { wallet } = await useWallet();
const { lobby } = await useLobby();
const { truncAddress } = await useEthUtils();
const {
  chess,
  fen,
  legalMoves,
  gameContract,
  moves,
  gameData,
  opponent,
  isCurrentMove,
  isWhitePlayer,
  inCheck,
  inCheckmate,
  opponentInCheckmate,
  gameOver,
  isStalemate,
  isWinner,
  isLoser,
  registerListeners,
  destroyListeners,
  startMoveTimer,
  stopMoveTimer,
  timeOfExpiry,
  timeUntilExpiry,
  timerExpired,
  tryMove,
  submitMove,
  didSendMove,
  resign,
  didSendResign,
  claimVictory,
  offerStalemate,
  didOfferStalemate
} = await useChessEngine(gameId);

registerListeners();
startMoveTimer();
onUnmounted(() => {
  destroyListeners();
  stopMoveTimer();
});

const timerExpiredModal = ref(false);
const opponentTimerExpiredModal = ref(false);
const offerStalemateModal = ref(false);
const confirmStalemateModal = ref(false);
const confirmResignModal = ref(false);
const opponentResignedModal = ref(false);
//const checkmateModal = ref(false);
const inCheckmateModal = ref(!gameOver.value && inCheckmate.value);
watch(inCheckmate, () => inCheckmateModal.value = true);

const didChooseMove = ref(false);
const proposedMove = ref(null);
function chooseMove(from, to) {
  const move = chess.move({ from, to });
  fen.value = chess.fen();
  if (!move) throw Error('Illegal move', from, '->', to);
  console.log('Choose Move', move.san);
  proposedMove.value = move.san;
  didChooseMove.value = true;
}

function undoMove() {
  const move = chess.undo();
  console.log('Undo Move', move.san);
  fen.value = chess.fen();
  didChooseMove.value = false;
}

const displayTimer = computed(() => {
  if (timeUntilExpiry.value > 3600) {         // > 1 hour
    return humanizeDuration.humanizer({
      language: 'shortEn',
      languages: {
        shortEn: {
          y: () => 'year',
          mo: () => 'months',
          w: () => 'weeks',
          d: () => 'days',
          h: () => 'hours',
          m: () => 'mins',
          s: () => 'secs'
        }
      }
    })(timeUntilExpiry.value*1000, { largest: 2, delimiter: ' ' });
  } else {                                    // < 1 hour
    const mins = Math.floor(timeUntilExpiry.value / 60);
    const secs = timeUntilExpiry.value % 60;
    return `${mins}`.padStart(2, 0) + ':' + `${secs}`.padStart(2, 0);
  }
});
</script>

<template lang='pug'>
NuxtLayout(name='game')
  template(v-slot:board)
    ChessBoard(
      v-bind='{ fen, legalMoves, isWhitePlayer, isCurrentMove }'
      @moved='chooseMove'
    )

  template(v-slot:info)
    div(id='caption')
      div(v-if='gameOver' class='text-lg font-bold') Game Over
      div(v-else class='text-lg font-bold') In Progress
      div(id='timer')
        div(v-if='gameOver') -- : --
        div(v-else-if='!timerExpired') {{ displayTimer }}
        div(v-else) Timer Expired
      div(id='opponent' class='text-xs') {{ truncAddress(opponent) }}
      div(id='action-indicator')
        div(v-if='isWinner') You Won!
        div(v-else-if='isLoser') You Lost
        div(v-else-if='inCheckmate') Checkmate!
        div(v-else-if='inCheck') Check!
        div(v-else-if='didSendMove') Pending...
        div(v-else-if='didChooseMove') Submit Move
        div(v-else-if='isCurrentMove') Your Move
        div(v-else) Opponent's Move

    div(id='moves' class='text-sm')
      div(v-for='m in moves') {{ m }}

    div(id='controls' class='pb-2')
      div(id='controlbar' class='p-2 flex justify-between')
        button(
          title='Undo Move'
          class='unbordered'
          :disabled='!didChooseMove || didSendMove'
          @click='undoMove'
        )
          img(class='w-6' src='~assets/icons/bytesize/trash.svg')
        button(
          title='Offer Draw'
          class='unbordered'
          @click='() => offerStalemateModal = true'
          disabled
        )
          img(class='w-6' src='~assets/icons/bytesize/flag.svg')
        button(
          title='Resign'
          class='unbordered'
          @click='() => confirmResignModal = true'
          :disabled='gameOver'
        )
          img(class='w-6' src='~assets/icons/bytesize/ban.svg')

      button(
        title='Resign'
        v-if='!isCurrentMove && !gameOver && opponentInCheckmate'
        :disabled='!timerExpired'
        @click='claimVictory'
      ) Claim Victory
      button(
        title='Resign'
        v-else-if='!gameOver && inCheckmate'
        :disabled='!inCheckmate'
        @click='resign'
      ) Resign
      button(
        title='Submit Move'
        v-else
        :disabled='!didChooseMove'
        @click='() => submitMove(proposedMove).then(() => didChooseMove = false)'
      ) Submit

    ConfirmModal(
      title='Resign?'
      v-if='confirmResignModal'
      :loading='didSendResign'
      @confirm='() => resign().then(() => confirmResignModal = false)'
      @close='() => confirmResignModal = false'
    )
      div Please confirm you wish to resign by clicking "Confirm".  By resigning, your fair-play deposit will be refunded.

    ConfirmModal(
      title='Offer Stalemate'
      v-if='offerStalemateModal'
      :loading='didOfferStalemate'
      @confirm='offerStalemate'
      @close='() => offerStalemateModal = false'
    )
      div By clicking "Confirm", you'll offer your opponent the opportunity to end the game as a draw.  Both players will receive their wagers back.

    Modal(
      title='Checkmate!'
      v-if='inCheckmateModal'
      @close='() => inCheckmateModal = false'
    )
      div(class='text-center') Oh no, you're in checkmate!  Please resign before the timer expires to be refunded your fair-play deposit.
      div(id='form-controls' class='flex items-center')
        button(
          @click='() => resign().then(() => inCheckmateModal = false)'
          :disabled='didSendResign'
        ) Resign
</template>

<style lang='sass'>
#info
  #moves
    @apply my-4

    div
      @apply flex px-4
    div:nth-child(odd)
      @apply justify-start
    div:nth-child(even)
      @apply justify-end bg-gray-200
</style>
