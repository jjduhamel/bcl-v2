// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/utils/structs/EnumerableMap.sol';
import '@oz/utils/Counters.sol';

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

  struct LobbyMetadata {
    Counters.Counter gamesCreated;
    Counters.Counter gamesStarted;
    Counters.Counter gamesFinished;
    uint netWagers;
    uint netEarnings;
  }

  struct PlayerMetadata {
    Counters.Counter challengesSent;
    Counters.Counter challengesReceived;
    Counters.Counter gamesStarted;
    Counters.Counter gamesWon;
    Counters.Counter gamesLost;
    Counters.Counter gamesDrawn;
    uint netWagers;
    uint netWinnings;
    uint netLosses;
  }

  struct PlayerLobby {
    EnumerableSet.UintSet pendingChallenges;
    EnumerableSet.UintSet currentGames;
    EnumerableSet.UintSet finishedGames;
  }
}
