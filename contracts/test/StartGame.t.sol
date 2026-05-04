// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract StartGameTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    changePrank(p2);
  }

  function testInitialGameData() public {
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Started));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
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

  function testSomeLegalMoves() public {
    _testMove(p1, 'a2a3');
    _testMove(p2, 'b7b6');
    _testMove(p1, 'c2c4');
    _testMove(p2, 'd7d5');
  }

  function testFirstMoveAsBlackFails() public {
    vm.expectRevert(ChessEngine.NotCurrentMove.selector);
    _move(p2, 'b7b6');
  }

  function testKingCapture() public
    testEarnings(p1, 0)
    testEarnings(p2, 2*wager)
    testOutcome(GameOutcome.BlackWon)
    testWinner(p2)
    testLoser(p1)
  {
    _testMove(p1, 'f2f3');
    _testMove(p2, 'e7e5');
    _testMove(p1, 'g2g4');
    _testMove(p2, 'd8h4');
    _testMove(p1, 'a2a3');
    _testMove(p2, 'h4e1');
  }

  function testConsecutiveMoveFails() public {
    _testMove(p1, 'a2a3');
    vm.expectRevert(ChessEngine.NotCurrentMove.selector);
    _move(p1, 'b2b4');
  }
}
