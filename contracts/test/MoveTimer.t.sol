// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract MoveTimerTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a3');
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.timeOfLastMove > 0);
  }

  function testTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    _testMove(p2, 'b6');
  }

  function testTimerAlmostExpired() public {
    skip(timePerMove);
    testTimerActive();
  }

  function testTimerExpired() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    vm.expectRevert('TimerExpired');
    _move(p2, 'b6');
  }
}

contract ClaimVictoryTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a3');
    changePrank(p1);
  }

  function testClaimVictoryFailsWhileTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    vm.expectRevert('TimerActive');
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsWinner() public
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
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
    vm.expectRevert('NotOpponentsMove');
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsSpectator() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.claimVictory(gameId);
  }
}
