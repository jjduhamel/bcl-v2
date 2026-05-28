<template lang='pug'>
section(class='max-w-3xl mx-auto px-4 py-6 flex flex-col gap-2')
  h1(class='text-2xl font-bold mb-1') Welcome
  div Thanks for visiting The Blockchain Chess Lounge!  This was originally developed as a project for Buildspace Nights & Weekends.  The idea was to develop a peer-to-peer game of chess which enabled trustless wagering.  Below, you'll find a description of the rules and a few caveats.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Rules
    div(class='mb-2') The standard of chess apply, with a few notes specific to this contract:
    ul(class='list-disc list-outside space-y-1 pl-6')
      li There is no automated checkmate detection — if your opponent is in checkmate, you can capture the king and end the game.
      li Each player has a certain amount of time to move. If you exceed it, your opponent can claim victory.
      li Either player may resign at any time.
      li En passant is not supported.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Disputes
    div(class='mb-2') Running a full chess rule validator on chain would cost an enormous amount of gas per move.  To keep games cheap, the contract doesn't check whether a move leaves either king in check or checkmate.  Those higher-order rules are delegated to the players: if your opponent breaks one, you can raise a dispute.
    ul(class='list-disc list-outside space-y-1 pl-6')
      li If your opponent submits an illegal move that the contract still accepts, you will be prompted to dispute the game.
      li To resolve a dispute, an arbiter will review the game. The arbiter will assign the winner based on whether an illegal move has been submitted.  Disputing a legal move will result in losing the game.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Wagers
    div(class='mb-2') Players can optionally wager ETH and ERC20 tokens on the outcome of the game. The contract holds the wagers in escrow until the game ends.
    ul(class='list-disc list-outside space-y-1 pl-6')
      li Players deposit a wager at the time of creating, modifying, or accepting a challenge.
      li If a player deposits too much, the excess amount will be refunded when the challenge is accepted.
      li Declining a challenge refunds the wagers to both players.  No platform fees are charged in this case.
      li When the game ends, the winner receives both wagers. On a draw, both wagers are refunded.
      li You must withdraw your winnings, it is not paid automatically.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Stalemate
    div(class='mb-2') In the case of the stalemate, you can offer to end the game in a draw.  Your opponent has to respond within the time alotted for them to make a move.
    ul(class='list-disc list-outside space-y-1 pl-6')
      li If you're in a stalemate, you can send your opponent an offer to finish the game as a Draw.
      li This temporarily pauses the game, and your opponent has to accept or decline your offer within the alotted time-per-move.
      li If your opponent declines you may dispute the game.  If you're in a legimate stalemate, an arbiter will settle the game as a draw and your wager will be refunded.

  div(class='mt-2')
    h1(class='text-xl font-bold mb-1') Platform Fees
    ul(class='list-disc list-outside space-y-1 pl-6')
      li A flat 2% fee is charged on both wagers when the game starts.
      li Games with no wager are free to play.
</template>
