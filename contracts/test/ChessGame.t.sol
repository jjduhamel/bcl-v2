// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import 'forge-std/console2.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';
import 'test/Challenge.t.sol';

abstract contract ChessGameTest is ChallengeTest {
  constructor() {
    changePrank(p1);
    lobby.challenge{ value: wager }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges();
    gameId = challenges[0];
    changePrank(p2);
    engine.acceptChallenge{ value: wager }(gameId);
    changePrank(p1);
  }
}

contract StartGameTest is ChessGameTest {
  function _testAccepted(address player) public {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 1);
    assertEq(games[0], gameId);
  }

  function testInitialGameData() public {
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(ChessEngine.GameState.Started));
    assertEq(uint(gameData.outcome), uint(ChessEngine.GameOutcome.Undecided));
    assertEq(gameData.whitePlayer, p1);
    assertEq(gameData.blackPlayer, p2);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.timePerMove, timePerMove);
    assertGt(gameData.timeOfLastMove, 0);
    assertEq(gameData.wagerAmount, wager);
  }

  function testFetchDataAsPlayer3() public {
    changePrank(p3);
    testInitialGameData();
  }

  function _move(address player, string memory san) private {
    changePrank(player);
    engine.move(gameId, san);
  }

  function _testMove(address player, string memory san) private {
    vm.expectEmit(true, true, true, true);
    emit MoveSAN(gameId, player, san);
    _move(player, san);
    string[] memory moves = engine.moves(gameId);
    if (moves.length == 0) return;
    assertEq(moves[moves.length-1], san);
  }

  function testSomeLegalMoves() public {
    _testMove(p1, 'a3');
    _testMove(p2, 'b6');
    _testMove(p1, 'c4');
    _testMove(p2, 'd5');
  }

  function testFirstMoveAsBlackFails() public {
    vm.expectRevert('NotCurrentMove');
    _move(p2, 'b6');
  }

  function testConsecutiveMoveFails() public {
    _testMove(p1, 'a3');
    vm.expectRevert('NotCurrentMove');
    _move(p1, 'b4');
  }

  function testAcceptChallengeFails() public {
    vm.expectRevert('InvalidContractState');
    engine.acceptChallenge(gameId);
  }

  function testDeclineChallengeFails() public {
    vm.expectRevert('InvalidContractState');
    engine.declineChallenge(gameId);
  }

  function testModifyChallengeFails() public {
    vm.expectRevert('InvalidContractState');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }

  function testResignAsPlayer1() public {
    engine.resign(gameId);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(ChessEngine.GameState.Finished));
    assertEq(uint(gameData.outcome), uint(ChessEngine.GameOutcome.BlackWon));
  }

  function testResignAsPlayer2() public {
    changePrank(p2);
    engine.resign(gameId);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(ChessEngine.GameState.Finished));
    assertEq(uint(gameData.outcome), uint(ChessEngine.GameOutcome.WhiteWon));
  }

  function testResignAsPlayer3Fails() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.resign(gameId);
  }
}

contract GameTimerTest is ChessGameTest {
  // TODO claimVictory
}
