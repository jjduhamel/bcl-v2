// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import './Challenge.t.sol';

abstract contract ChessGameTest is ChallengeTest {
  constructor() {
    changePrank(p1);
    lobby.challenge{ value: wager }(p1, p2, true, timePerMove, wager, address(0));
    uint[] memory challenges = lobby.challenges(p1);
    gameId = challenges[0];
    changePrank(p2);
  }

  function _move(address player, string memory uci) internal {
    changePrank(player);
    engine.move(gameId, uci);
  }

  function _testMove(address player, string memory uci) internal {
    vm.expectEmit(true, true, true, true, address(engine));
    emit PlayerMoved(gameId, player, uci);
    _move(player, uci);
    string[] memory moves = engine.moves(gameId);
    if (moves.length == 0) return;
    assertEq(moves[moves.length-1], uci);
  }

  modifier expectGameOver(address winner, address loser) {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameOver(gameId, winner, loser);
    _;
  }

  modifier testOutcome(GameOutcome outcome) {
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == outcome);
  }

  modifier testWinner(address player) {
    uint wins = lobby.gameStats(player).won;
    uint winnings = totalWinnings(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.winner(gameId), player);
    assertEq(lobby.gameStats(player).won, wins+1);
    assertEq(totalWinnings(player), winnings+gameData.wagerAmount);
  }

  modifier testLoser(address player) {
    uint lost = lobby.gameStats(player).lost;
    uint losses = totalLosses(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.loser(gameId), player);
    assertEq(lobby.gameStats(player).lost, lost+1);
    assertEq(totalLosses(player), lost+gameData.wagerAmount);
  }

  modifier testDraw(address player) {
    uint draws = lobby.gameStats(player).draws;
    uint winnings = totalWinnings(player);
    uint losses = totalLosses(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.winner(gameId), address(0));
    assertEq(engine.loser(gameId), address(0));
    assertEq(lobby.gameStats(player).draws, draws+1);
    assertEq(totalWinnings(player), winnings);
    assertEq(totalLosses(player), losses);
  }
}
