<template lang='pug'>
section(class='max-w-3xl mx-auto px-4 py-6 flex flex-col gap-2')
  h1(class='text-2xl font-bold mb-1') Welcome
  div Thanks for checking out The Blockchain Chess Lounge!  This was originally developed as a project for Buildspace Nights & Weekends.  The idea was to develop a peer-to-peer game of chess which enabled trustless wagering.  Below, you'll find a description of the rules and a few caveats.
  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Rules
    div(class='mb-2') The standard of chess apply, with a few notes specific to this contract:
    ul(class='list-disc list-outside space-y-1 pl-6')
      li There is no automated checkmate detection on chain — if your opponent is in checkmate, you can capture the king and end the game.
      li Each player has a certain amount of time to move. If you exceed it, your opponent can claim victory.
      li Either player may resign at any time.
      li En passant is not supported.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Disputes
    div(class='mb-3') Running a full chess rule validator on chain would cost an enormous amount of gas per move. To keep games cheap, the contract only enforces piece-movement geometry — it doesn't check whether a move leaves the moving player's king in check, and it can't detect checkmate. Those higher-order rules are delegated to the players: if your opponent breaks one, you raise a dispute.
    ul(class='list-disc list-outside space-y-1 pl-6')
      li(class='mb-3') If your opponent submits an illegal move that the contract still accepts, you will be prompted to dispute the game.
      li To resolve a dispute, an arbiter will review the game. The arbiter will assign the winner based on whether an illegal move has been submitted.  Disputing a legal move will result in losing the game.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Platform Fees
    ul(class='list-disc list-outside space-y-1 pl-6')
      li(class='mb-2') A flat 2% fee is charged on both wagers when the game starts.
      li Games with no wager are free to play.
</template>
