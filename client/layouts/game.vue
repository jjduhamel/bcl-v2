<script setup>
// The board is a square bounded by both the available height and the width left
// after the info panel — `min(w, h)` with shrink-wrap (whitespace stays on the
// right), which CSS can't express. Size it here, and pin the footer (in the
// parent layout) to span the resulting content width. Both reset on unmount.
const game = ref(null);
const board = ref(null);
const info = ref(null);

onMounted(() => {
  const footer = document.getElementById('footer');

  const bodyEl = document.getElementById('body');
  const sidebar = document.getElementById('sidebar');
  const content = document.getElementById('content');

  const layout = () => {
    const chessboard = board.value.querySelector('#chessboard');
    if (!chessboard || !bodyEl || !sidebar) return;
    const pad = getComputedStyle(board.value);
    const padX = parseFloat(pad.paddingLeft) + parseFloat(pad.paddingRight);
    const padY = parseFloat(pad.paddingTop) + parseFloat(pad.paddingBottom);

    // Available width from stable elements — not #game, whose width is inflated by
    // the board itself (circular) and overflows on narrow windows.
    const bodyCS = getComputedStyle(bodyEl);
    const innerW = bodyEl.clientWidth
      - parseFloat(bodyCS.paddingLeft) - parseFloat(bodyCS.paddingRight)
      - sidebar.offsetWidth
      - parseFloat(getComputedStyle(content).marginLeft);

    // min(width left after the caption, height), with a rem floor so the board
    // never shrinks below a usable size; past that the layout overflows.
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
    const availW = innerW - info.value.offsetWidth - padX;
    const availH = Math.min(game.value.clientHeight - padY, 56*rem)
    const size = Math.max(24*rem, Math.min(availW, availH));
    chessboard.style.width = chessboard.style.height = `${size}px`;

    // Match the info column to the board's bottom edge so the controls (Submit)
    // line up with the bottom of the board rather than the full game height.
    info.value.style.height = `${size + parseFloat(pad.paddingTop)}px`;

    if (footer) {
      const left = footer.getBoundingClientRect().left;
      footer.style.width = `${info.value.getBoundingClientRect().right - left}px`;
    }
  };

  // Observe the body (width/height) and sidebar (its width varies with wallet
  // state); both are unaffected by the board, so there's no resize loop.
  const ro = new ResizeObserver(layout);
  ro.observe(bodyEl);
  ro.observe(sidebar);
  window.addEventListener('resize', layout);
  layout();

  onUnmounted(() => {
    ro.disconnect();
    window.removeEventListener('resize', layout);
    if (footer) footer.style.width = '';
  });
});
</script>

<template lang='pug'>
div(id='game' ref='game')
  div(id='board' ref='board')
    slot(name='board')
  div(id='info' ref='info')
    slot(name='info')
</template>

<style lang='sass'>
#game
  @apply flex flex-grow min-h-0 items-start
  height: 100%

  // No flex-grow: the board column shrink-wraps to the board so the layout
  // doesn't stretch full-width. Extra horizontal room becomes whitespace on
  // the right (#game packs its children to the start).
  #board
    @apply pl-4 pr-8 py-2 flex items-start min-h-0

    // Width/height set in script to the min(width, height) square.
    #chessboard
      .cg-wrap
        width: 100%
        height: 100%

        coords coord
          @apply text-sm font-bold

  #info
    @apply w-48 shrink-0 flex flex-col

    .bordered
      @apply p-2 border border-2 border-black rounded-xl

    #caption
      @apply flex-shrink text-center text-sm
      @extend .bordered

    #moves
      @apply flex-1 overflow-auto

    #controls
      @apply justify-end flex flex-col px-2

      button
        @apply flex-1
</style>
