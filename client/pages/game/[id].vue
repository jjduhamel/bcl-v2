<script setup>
import _ from 'lodash';

definePageMeta({
  middleware: [ 'auth' ]
});

const { params } = useRoute();
const gameId = params.id;
const { wallet } = await useWallet();
const { lobby } = await useLobby();
const { playAudioClip } = useAudioUtils();
const {
  chess,
  fen,
  legalMoves,
  moves,
  illegalMoves,
  fetchMoves,
  gameData,
  opponent,
  wagerAmount,
  isSpectator,
  isCurrentMove,
  isOpponentsTurn,
  isWhitePlayer,
  inCheck,
  inCheckmate,
  opponentInCheckmate,
  checkmatePending,
  opponentCheckmatePending,
  kingCaptureUci,
  canCaptureKing,
  gameOver,
  isDisputed,
  isStalemate,
  inDrawOffer,
  drawOfferReceived,
  drawOfferSent,
  isWinner,
  isLoser,
  timeOfExpiry,
  timeUntilExpiry,
  timerExpired,
  playerTimeExpired,
  opponentTimeExpired,
  tryMove,
  submitMove,
  resign,
  claimVictory,
  offerStalemate,
  respondDraw,
  withdrawWinnings,
  disputeGame,
  startMoveTimer,
  stopMoveTimer,
  registerListeners,
  destroyListeners,
} = await useChessEngine(gameId);

// Orient the board from the side the viewer controls (own seat or an owned
// agent); a spectator with no seat defaults to white on bottom.
const whiteOnBottom = computed(() => !lobby.controls(gameData.value.blackPlayer));

// When the current mover is one of my agents, moves arrive via gasless UserOps
// from the agent's MCP process — the wallet must not double-submit, so the
// board goes view-only and the caption swaps to an "agent thinking" status.
const currentAgent = computed(() => lobby.ownedAgent(gameData.value.currentMove));
const isAgentMoveTurn = computed(() => !!currentAgent.value);

const disputedMove = ref(null);
watch(illegalMoves, () => {
  // After tryMove advances the board, the turn flips to whoever moves next.
  // If it's now our turn, the opponent just played an illegal-but-accepted
  // move — that's the dispute case. (Own illegal moves leave isOpponentsTurn
  // true here; EP rejections never reach the contract so checking !rejected
  // is defensive.)
  if (isOpponentsTurn.value) return;
  const j = _.last(illegalMoves.value);
  const move = moves.value[j];
  if (!move?.illegal || move.rejected) return;
  console.log('Dispute move', move.uci);
  disputedMove.value = move;
});

const playerTimeExpiredModal = ref(playerTimeExpired.value);
const opponentTimeExpiredModal = ref(opponentTimeExpired.value);
const offerStalemateModal = ref(false);
const confirmStalemateModal = ref(false);
const confirmResignModal = ref(false);
const opponentResignedModal = ref(false);
//const checkmateModal = ref(false);
const inCheckmateModal = ref(false);
const illegalMoveModal = ref(false);
// Auto-opens when the opponent's OfferedDraw event flips drawOfferReceived true.
// Seeded from the current ref so a page refresh while a draw is pending also
// surfaces the prompt. Same pattern for drawOfferSentModal so the sender gets a
// one-time "waiting on opponent" acknowledgement they can dismiss.
const respondDrawModal = ref(drawOfferReceived.value);
const drawOfferSentModal = ref(drawOfferSent.value);

watch(playerTimeExpired, () => playerTimeExpiredModal.value = true);
watch(opponentTimeExpired, () => opponentTimeExpiredModal.value = true);
watch(inCheckmate, () => inCheckmateModal.value = !didChooseMove && !!inCheckmate.value);
watch(disputedMove, () => illegalMoveModal.value = !didChooseMove);
watch(drawOfferReceived, v => { if (v) respondDrawModal.value = true; });
watch(drawOfferSent, v => { if (v) drawOfferSentModal.value = true; });

const proposedMove = ref(null);
const didChooseMove = ref(false);
// FEN before the current choice. We snapshot uniformly (not just for castling)
// because tryMove can take three different paths — chess.move (history pushed),
// applyManually's pseudo-legal branch (history pushed via _makeMove), and
// applyCastleManually (history wiped by chess.load). Restoring via chess.load
// always works; chess.undo() would silently fail on the castle path.
const fenBeforeChoose = ref(null);
function chooseMove(from, to) {
  const piece = chess.get(from);
  const promotion = piece?.type === 'p' && (to[1] === '8' || to[1] === '1') ? 'q' : '';
  fenBeforeChoose.value = fen.value;
  const move = tryMove(`${from}${to}${promotion}`);
  proposedMove.value = move;
  didChooseMove.value = true;
  playAudioClip('nes/Move');
}

function undoMove() {
  console.log('Undo Move', proposedMove.value?.uci);
  chess.load(fenBeforeChoose.value);
  fen.value = fenBeforeChoose.value;
  // tryMove flags illegal/rejected moves by appending moves.value.length to
  // illegalMoves. Since the move was never confirmed (moves[] hasn't grown),
  // pop that trailing index so the list stays aligned with moves[].
  if (_.last(illegalMoves.value) === moves.value.length) {
    illegalMoves.value.pop();
  }
  didChooseMove.value = false;
  proposedMove.value = null;
}

const didSendMove = ref(false);
async function doSendMove() {
  try {
    didSendMove.value = true;
    await submitMove(proposedMove.value.uci);
    didChooseMove.value = false;
    proposedMove.value = null;
  } catch (err) {
    console.error(err);
    // Tx reverted (or some other failure) — roll the board back to the
    // pre-choose state. undoMove restores from fenBeforeChoose, pops the
    // trailing illegalMoves entry, and resets proposedMove / didChooseMove.
    undoMove();
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

const didRespondDraw = ref(false);
async function doRespondDraw(accept) {
  try {
    didRespondDraw.value = true;
    await respondDraw(accept);
  } catch (err) {
    console.error(err);
  } finally {
    didRespondDraw.value = false;
  }
}

const didWithdrawWinnings = ref(false);
async function doWithdrawWinnings() {
  try {
    didWithdrawWinnings.value = true;
    await withdrawWinnings();
  } catch (err) {
    console.error(err);
  } finally {
    didWithdrawWinnings.value = false;
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

async function doClaimKingCapture() {
  const uci = kingCaptureUci.value;
  // Route through chooseMove so the board visually advances first; then the
  // existing send-move pipeline submits the UCI and handles tx-revert rollback.
  chooseMove(uci.slice(0, 2), uci.slice(2, 4));
  await doSendMove();
}

function isIllegalMove(j) {
  return illegalMoves.value.includes(j);
}

// White moves at even indices, black at odd. Position by player so the
// active player's moves are always on the left.
function isPlayerMove(j) {
  return (j % 2 === 0) === whiteOnBottom.value;
}


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
      v-bind='{ fen, legalMoves, isCurrentMove }'
      :isWhitePlayer='whiteOnBottom'
      :viewOnly='isSpectator || isAgentMoveTurn'
      @moved='chooseMove'
    )

  template(v-slot:info)
    GameCaption(
      v-bind='{ isDisputed, inCheck, inCheckmate, opponentInCheckmate, isCurrentMove, didChooseMove, didSendMove, timerExpired, timeUntilExpiry, wagerAmount, opponent, isSpectator, isWhitePlayer }'
      :gameOutcome='gameData.outcome'
      :whitePlayer='gameData.whitePlayer'
      :blackPlayer='gameData.blackPlayer'
      :currentMove='gameData.currentMove'
      :isAgentMoveTurn='isAgentMoveTurn'
      :agentNickname='currentAgent?.nickname ?? ""'
    )

    div(id='moves' class='my-4 text-sm')
      div(
        v-for='(move, j) in moves'
        :class='[isPlayerMove(j) ? "player" : "opponent", j % 2 === 0 ? "white" : "black"]'
        :style='isIllegalMove(j) && { color: "red" }'
      ) {{ move.san ?? move.uci }}

    template(v-if='!isSpectator')
      GameControls(
        v-bind='{ didChooseMove, didSendMove, didWithdrawWinnings, gameOver, isDisputed, isWinner, isCurrentMove, inDrawOffer, checkmatePending, playerTimeExpired, opponentTimeExpired, canCaptureKing }'
        @undo='undoMove'
        @offer-draw='() => offerStalemateModal = true'
        @resign='() => confirmResignModal = true'
        @resign-now='doResign'
        @submit='doSendMove'
        @claim-victory='doClaimVictory'
        @claim-king-capture='doClaimKingCapture'
        @claim-winnings='doWithdrawWinnings'
      )

      ConfirmModal(
        title='Resign?'
        v-if='confirmResignModal'
        :loading='didSendResign'
        @confirm='() => doResign()\
            .then(() => confirmResignModal = false)'
        @close='() => confirmResignModal = false'
      )
        div Please confirm you wish to resign by clicking "Confirm".

      ConfirmModal(
        title='Offer Stalemate'
        v-if='offerStalemateModal'
        :loading='didOfferStalemate'
        @confirm='() => doOfferStalemate()\
            .then(() => offerStalemateModal = false)'
        @close='() => offerStalemateModal = false'
      )
        div By clicking "Confirm", you'll offer your opponent the opportunity to end in a draw.  Both players will receive their wagers back.

      Modal(
        title='Checkmate!'
        v-if='inCheckmateModal'
        @close='() => inCheckmateModal = false'
      )
        div(class='text-center') Oh no!  You're in checkmate.  Please resign before the timer expires.
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
        div(class='text-center') You ran out of time to make a move!  Please resign now.
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
        v-if='!gameOver && !isDisputed && !opponentInCheckmate && illegalMoveModal'
        @close='() => illegalMoveModal = false'
      )
        div(class='text-center') Your opponent submitted an illegal move.  Please send a dispute before your move expires and an arbiter will review the game.
        div(id='form-controls' class='flex items-center')
          button(
            @click='() => doDisputeGame()\
              .then(() => illegalMoveModal = false)'
            :disabled='didDisputeGame'
          ) Dispute

      Modal(
        title='Draw Offer'
        v-if='drawOfferReceived && respondDrawModal'
        @close='() => respondDrawModal = false'
      )
        div(class='text-center') Your opponent has offered a draw.  If you accept, both players will receive their wagers back.
        div(id='form-controls' class='flex items-center')
          button(
            @click='() => doRespondDraw(true)\
              .then(() => respondDrawModal = false)'
            :disabled='didRespondDraw'
          ) Accept
          button(
            @click='() => doRespondDraw(false)\
              .then(() => respondDrawModal = false)'
            :disabled='didRespondDraw'
          ) Decline

      Modal(
        title='Draw Offered'
        v-if='drawOfferSent && drawOfferSentModal'
        @close='() => drawOfferSentModal = false'
      )
        div(class='text-center') Waiting for your opponent to respond to your draw offer.
</template>

<style lang='sass'>
#info
  #moves
    div
      @apply flex px-4
    div.player
      @apply justify-start
    div.opponent
      @apply justify-end
    div.white
      @apply bg-transparent
    div.black
      @apply bg-gray-200
</style>
