<script setup>
import _ from 'lodash';
import humanizeDuration from 'humanize-duration';

const { params } = useRoute();
const gameId = params.id;
const { wallet } = await useWallet();
const { lobby } = await useLobby();
const { truncAddress } = useEthUtils();
const { playAudioClip } = useAudioUtils();
const {
  chess,
  fen,
  legalMoves,
  moves,
  illegalMoves,
  fetchMoves,
  opponent,
  isCurrentMove,
  isOpponentsTurn,
  isWhitePlayer,
  inCheck,
  inCheckmate,
  opponentInCheckmate,
  checkmatePending,
  opponentCheckmatePending,
  gameOver,
  isStalemate,
  isWinner,
  isLoser,
  timeOfExpiry,
  timeUntilExpiry,
  timerExpired,
  playerTimeExpired,
  opponentTimeExpired,
  tryMoveFromTo,
  submitMove,
  resign,
  claimVictory,
  offerStalemate,
  disputeGame,
  startMoveTimer,
  stopMoveTimer,
  registerListeners,
  destroyListeners,
} = await useChessEngine(gameId);

const disputedMove = ref(null);
/*
watch(illegalMoves, () => {
  if (isOpponentsTurn.value) {
    const j = _.last(illegalMoves.value);
    const san = moves.value[j]
    console.log('Dispute move', san);
    disputedMove.value = san;
  }
});
*/

const playerTimeExpiredModal = ref(playerTimeExpired.value);
const opponentTimeExpiredModal = ref(opponentTimeExpired.value);
const offerStalemateModal = ref(false);
const confirmStalemateModal = ref(false);
const confirmResignModal = ref(false);
const opponentResignedModal = ref(false);
//const checkmateModal = ref(false);
const inCheckmateModal = ref(false);
const illegalMoveModal = ref(false);

watch(playerTimeExpired, () => playerTimeExpiredModal.value = true);
watch(opponentTimeExpired, () => opponentTimeExpiredModal.value = true);
watch(inCheckmate, () => inCheckmateModal.value = true);
watch(disputedMove, () => illegalMoveModal.value = true);

const proposedMove = ref(null);
const didChooseMove = ref(false);
function chooseMove(from, to) {
  const san = tryMoveFromTo(from, to);
  proposedMove.value = san;
  didChooseMove.value = true;
  playAudioClip('nes/Move');
}

function undoMove() {
  const move = chess.undo();
  console.log('Undo Move', move.san);
  fen.value = chess.fen();
  didChooseMove.value = false;
}

const didSendMove = ref(false);
async function doSendMove() {
  try {
    didSendMove.value = true;
    await submitMove(proposedMove.value);
    didChooseMove.value = false;
    proposedMove.value = null;
  } catch (err) {
    console.error(err);
  } finally {
    didSendMove.value = false;
  }
}

const didSendResign = ref(false);
async function doResign() {
  try {
    didSendResign.value = true;
    await resign();
  } catch (err) {
    console.error(err);
  } finally {
    didSendResign.value = false;
  }
}

const didClaimVictory = ref(false);
async function doClaimVictory() {
  try {
    didClaimVictory.value = true;
    await claimVictory();
  } catch (err) {
    console.error(err);
  } finally {
    didSendResign.value = false;
  }
}

const didOfferStalemate = ref(false);
async function doOfferStalemate() {
  try {
    didOfferStalemate.value = true;
    await offerStalemate();
  } catch (err) {
    console.error(err);
  } finally {
    didOfferStalemate.value = false;
  }
}

const didDisputeGame = ref(false);
async function doDisputeGame() {
  try {
    didDisputeGame.value = true;
    await disputeGame();
  } catch (err) {
    console.error(err);
  } finally {
    didDisputeGame.value = false;
  }
}

function isIllegalMove(j) {
  return illegalMoves.value.includes(j);
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

console.log('Initialize game', gameId, 'against', opponent.value);
await fetchMoves();

registerListeners();
startMoveTimer();

onUnmounted(() => {
  destroyListeners();
  stopMoveTimer();
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
        div(v-else-if='inCheckmate || opponentInCheckmate') Checkmate!
        div(v-else-if='inCheck') Check!
        div(v-else-if='didSendMove') Pending...
        div(v-else-if='didChooseMove') Submit Move
        div(v-else-if='isCurrentMove') Your Move
        div(v-else) Opponent's Move

    div(id='moves' class='text-sm')
      div(
        v-for='(san, j) in moves'
        :style='isIllegalMove(j) && { color: "red" }'
      ) {{ san }}

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
        v-if='checkmatePending || playerTimeExpired'
        @click='doResign'
      ) Resign
      button(
        title='Claim Victory'
        v-else-if='opponentTimeExpired'
        @click='doClaimVictory'
      ) Claim Victory
      button(
        title='Submit Move'
        v-else
        :disabled='!didChooseMove || didSendMove'
        @click='doSendMove'
      ) Submit

    ConfirmModal(
      title='Resign?'
      v-if='confirmResignModal'
      :loading='didSendResign'
      @confirm='() => doResign()\
          .then(() => confirmResignModal = false)'
      @close='() => confirmResignModal = false'
    )
      div Please confirm you wish to resign by clicking "Confirm".  By resigning, your fair-play deposit will be refunded.

    ConfirmModal(
      title='Offer Stalemate'
      v-if='offerStalemateModal'
      :loading='didOfferStalemate'
      @confirm='() => doOfferStalemate()\
          .then(() => offerStalemateModal = false)'
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
          @click='() => doResign()\
            .then(() => inCheckmateModal = false)'
          :disabled='didSendResign'
        ) Resign

    Modal(
      title='Time Expired'
      v-if='!gameOver && playerTimeExpiredModal'
      @close='() => playerTimeExpiredModal = false'
    )
      div(class='text-center') Oh no, you ran out of time!  Please resign now.  We hope you play again!
      div(id='form-controls' class='flex items-center')
        button(
          @click='() => doResign()\
            .then(() => playerTimeExpiredModal = false)'
          :disabled='didSendResign'
        ) Resign

    Modal(
      title='You Won!'
      v-if='!gameOver && opponentTimeExpiredModal'
      @close='() => opponentTimeExpiredModal = false'
    )
      div(class='text-center') Your opponent ran out of time.  In order to finish the game, you can claim victory.
      div(id='form-controls' class='flex items-center')
        button(
          @click='() => doClaimVictory()\
            .then(() => opponentTimeExpiredModal = false)'
          :disabled='didSendResign'
        ) Victory

    Modal(
      title='Illegal Move'
      v-if='!gameOver && illegalMoveModal'
      @close='() => illegalMoveModal = false'
    )
      div(class='text-center') Your opponent submitted an illegal move.  Please send a dispute before your move expires and an arbiter will review the game.
      div(id='form-controls' class='flex items-center')
        button(
          @click='() => doDisputeGame()\
            .then(() => illegalMoveModal = false)'
          :disabled='didDisputeGame'
        ) Dispute
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
