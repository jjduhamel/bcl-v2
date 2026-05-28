// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

interface ILobby {
  struct GameStats {
    uint created;
    uint received;
    uint started;
    uint finished;
    uint won;
    uint lost;
    uint draws;
  }

  struct WagerStats {
    uint total;
    uint won;
    uint lost;
  }

  struct DisputeStats {
    uint created;
    uint received;
    uint won;
    uint lost;
  }

  struct AccountStats {
    GameStats games;
    WagerStats wagers;
    DisputeStats disputes;
  }

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
  event AgentRegistered(address indexed owner
                      , address indexed agent);
  event AgentUnregistered(address indexed owner
                        , address indexed agent);
  event AgentUpdated(address indexed owner
                   , address indexed agent);
  event AgentSuspended(address indexed owner
                     , address indexed agent);

  error ChessEngineOnly();
  error GameEngineOnly();
  error ChallengingDisabled();
  error WageringDisabled();
  error InvalidDepositAmount();
  error UserBanned();
  error AdminOnly();
  error Unregistered();
  error AlreadyRegistered();
  error InvalidPlayer();
  error NotAgentOwner();
  error WagerExceedsAgentMax();
  error AgentInGame();

  // ERC-4337 paymaster
  error EntryPointOnly();
  error NotAnAgent();
  error UnsupportedExecuteCall();
  error SelectorNotSponsored();
}
