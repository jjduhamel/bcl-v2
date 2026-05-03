// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

interface ILobby {
  event TouchRecord(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event NewChallenge(uint indexed gameId
                   , address indexed player1
                   , address indexed player2);
  event ChallengeAccepted(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event ChallengeDeclined(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event GameFinished(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event GameDisputed(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event DisputeResolved(uint indexed gameId
                      , address indexed sender
                      , address indexed receiver);
}
