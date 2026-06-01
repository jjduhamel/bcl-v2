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

  modifier testEarnings(address player, uint expected) {
    _;
    address i = me.who();
    changePrank(player);
    assertEq(lobby.earnings(address(0)), expected);
    changePrank(i);
  }

  modifier testChallengeSent(uint gameId, address player) {
    uint nSent = lobby.gameStats(player).created;
    uint nRecv = lobby.gameStats(player).received;
    _;
    uint[] memory challenges = lobby.challenges(player);
    assertEq(lobby.gameStats(player).created, nSent+1);
    assertEq(lobby.gameStats(player).received, nRecv);
    assertEq(gameId, challenges[nSent+nRecv]);
  }

  modifier testChallengeReceived(uint gameId, address player) {
    uint nSent = lobby.gameStats(player).created;
    uint nRecv = lobby.gameStats(player).received;
    _;
    uint[] memory challenges = lobby.challenges(player);
    assertEq(lobby.gameStats(player).created, nSent);
    assertEq(lobby.gameStats(player).received, nRecv+1);
    assertEq(gameId, challenges[nSent+nRecv]);
  }

  modifier testGameStarted(uint gameId, address player) {
    uint nGames = lobby.gameStats(player).started;
    _;
    changePrank(player);
    uint[] memory games = lobby.games(player);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameId, games[nGames]);
    assertEq(lobby.gameStats(player).started, nGames+1);
    // Wager-total accumulation is timed to lock(), not game-start; testWinner/testLoser cover the
    // disburse-time accounting, and `EscrowFee` / `EscrowDisburse` suites cover the ledger.
    assertTrue(gameData.state == IChessEngine.GameState.Started);
    assertTrue(gameData.outcome == IChessEngine.GameOutcome.Undecided);
  }

  modifier testGameFinished(uint gameId, address player) {
    uint nGames = lobby.gameStats(player).finished;
    _;
    uint[] memory history = lobby.history(player);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(lobby.gameStats(player).finished, nGames+1);
    assertEq(gameId, history[nGames]);
    assertTrue(gameData.state == IChessEngine.GameState.Finished);
    assertFalse(gameData.outcome == IChessEngine.GameOutcome.Undecided);
  }
}
