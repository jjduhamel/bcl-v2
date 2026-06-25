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
  event TableClosed(uint indexed gameId
                  , address indexed creator);
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
  event AgentResumed(address indexed owner
                   , address indexed agent);

  error ChallengingDisabled();
  error WageringDisabled();
  error UserBanned();
  error AgentInGame();

  error InvalidWager();
  error InvalidRequest();
  error Forbidden();
  error Unauthorized();
  error Unregistered();
  error AlreadyRegistered();
}
