// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/ChessEngine.sol';
import './Lobby.t.sol';

abstract contract ChallengeTest is LobbyTest {
  uint gameId;

  constructor() {
    changePrank(arbiter);
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    changePrank(p1);
  }

  modifier testBalanceDelta(address player, int delta) {
    int initialBalance = int(player.balance);
    _;
    assertEq(int(player.balance)-initialBalance, delta);
  }

  modifier testChallengeSent(uint gameId, address player) {
    uint nSent = lobby.challengesSent(player);
    uint nRecv = lobby.challengesReceived(player);
    _;
    uint[] memory challenges = lobby.challenges(player);
    assertEq(lobby.challengesSent(player), nSent+1);
    assertEq(lobby.challengesReceived(player), nRecv);
    assertEq(gameId, challenges[nSent+nRecv]);
  }

  modifier testChallengeReceived(uint gameId, address player) {
    uint nSent = lobby.challengesSent(player);
    uint nRecv = lobby.challengesReceived(player);
    _;
    uint[] memory challenges = lobby.challenges(player);
    assertEq(lobby.challengesSent(player), nSent);
    assertEq(lobby.challengesReceived(player), nRecv+1);
    assertEq(gameId, challenges[nSent+nRecv]);
  }

  modifier testGameStarted(uint gameId, address player) {
    uint nGames = lobby.gamesStarted(player);
    uint wagers = totalWagers(player);
    _;
    changePrank(player);
    uint[] memory games = lobby.games(player);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameId, games[nGames]);
    assertEq(lobby.gamesStarted(player), nGames+1);
    assertEq(totalWagers(player), wagers+gameData.wagerAmount);
    assertTrue(gameData.state == IChessEngine.GameState.Started);
    assertTrue(gameData.outcome == IChessEngine.GameOutcome.Undecided);
  }

  modifier testGameFinished(uint gameId, address player) {
    uint nGames = lobby.gamesFinished(player);
    _;
    uint[] memory history = lobby.history(player);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(lobby.gamesFinished(player), nGames+1);
    assertEq(gameId, history[nGames]);
    assertTrue(gameData.state == IChessEngine.GameState.Finished);
    assertFalse(gameData.outcome == IChessEngine.GameOutcome.Undecided);
  }
}
