// SPDX-License-Identifier: GPL-V3
pragma solidity ^0.8.13;

interface GameEvents {
  event CreatedChallenge(uint indexed gameId
                       , address indexed player1
                       , address indexed player2);
  event AcceptedChallenge(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event DeclinedChallenge(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event TouchRecord(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event GameStarted(uint indexed gameId
                  , address indexed whitePlayer
                  , address indexed blackPlayer);
  event GameFinished(uint indexed gameId
                   , address indexed winner
                   , address indexed loser);
  event GameDisputed(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event PlayerMoved(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event MoveSAN(uint indexed gameId, address indexed player, string san);
  event ArbiterAction(address indexed arbiter, string comment);
}

