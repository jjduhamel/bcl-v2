// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract MoveTimerTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a2a3');
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.timeOfLastMove > 0);
  }

  function testTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    _testMove(p2, 'b7b6');
  }

  function testTimerAlmostExpired() public {
    skip(timePerMove);
    assertFalse(engine.timeDidExpire(gameId));
    _testMove(p2, 'b7b6');
  }

  function testTimerExpired() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    vm.expectRevert(ChessEngine.TimerExpired.selector);
    _move(p2, 'b7b6');
  }
}

contract ClaimVictoryTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a2a3');
    changePrank(p1);
  }

  function testClaimVictoryFailsWhileTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    vm.expectRevert(ChessEngine.TimerActive.selector);
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsWinner() public
    testEarnings(p1, 2*wager)
    testEarnings(p2, 0)
    testOutcome(GameOutcome.WhiteWon)
    testWinner(p1)
    testLoser(p2)
    expectGameOver(p1, p2)
  {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsLoser() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    changePrank(p2);
    vm.expectRevert(ChessEngine.NotOpponentsMove.selector);
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsSpectator() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    changePrank(p3);
    vm.expectRevert(ChessEngine.PlayerOnly.selector);
    engine.claimVictory(gameId);
  }
}
