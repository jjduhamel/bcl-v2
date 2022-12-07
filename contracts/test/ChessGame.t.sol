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
    lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges(p1);
    gameId = challenges[0];
    changePrank(p2);
  }

  function _move(address player, string memory san) internal {
    changePrank(player);
    engine.move(gameId, san);
  }

  function _testMove(address player, string memory san) internal {
    vm.expectEmit(true, true, true, true, address(engine));
    emit MoveSAN(gameId, player, san);
    _move(player, san);
    string[] memory moves = engine.moves(gameId);
    if (moves.length == 0) return;
    assertEq(moves[moves.length-1], san);
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
    uint wins = lobby.totalWins(player);
    uint winnings = totalWinnings(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.winner(gameId), player);
    assertEq(lobby.totalWins(player), wins+1);
    assertEq(totalWinnings(player), winnings+gameData.wagerAmount);
  }

  modifier testLoser(address player) {
    uint lost = lobby.totalLosses(player);
    uint losses = totalLosses(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.loser(gameId), player);
    assertEq(lobby.totalLosses(player), lost+1);
    assertEq(totalLosses(player), losses+gameData.wagerAmount);
  }

  modifier testDraw(address player) {
    uint draws = lobby.totalDraws(player);
    uint winnings = totalWinnings(player);
    uint losses = totalLosses(player);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertEq(engine.winner(gameId), address(0));
    assertEq(engine.loser(gameId), address(0));
    assertEq(lobby.totalDraws(player), draws+1);
    assertEq(totalWinnings(player), winnings);
    assertEq(totalLosses(player), losses);
  }
}
