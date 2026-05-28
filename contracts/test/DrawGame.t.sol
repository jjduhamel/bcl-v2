// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract DrawGameTest is ChessGameTest {
  function setUp() public {
    lobby.acceptChallenge{ value: wager }(gameId);
    changePrank(p1);
    engine.offerDraw(gameId);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Draw));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    changePrank(p2);
  }

  function testMoveFailsDuringDraw() public {
    vm.expectRevert(InvalidContractState.selector);
    _move(p2, 'b7b6');
  }

  function testAcceptDraw() public
    testOutcome(GameOutcome.Draw)
    testDraw(p1)
    testDraw(p2)
    testEarnings(p1, purse() / 2)
    testEarnings(p2, purse() / 2)
  {
    engine.respondDraw(gameId, true);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Finished));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Draw));
  }

  function testDeclineDraw() public
    testEarnings(p1, 0)
    testEarnings(p2, 0)
  {
    engine.respondDraw(gameId, false);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Started));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    _testMove(p1, 'a2a3');
    _testMove(p2, 'b7b6');
  }

  function testRespondDrawFailsAsSender() public {
    changePrank(p1);
    vm.expectRevert(NotCurrentMove.selector);
    engine.respondDraw(gameId, true);
  }

  function testRespondDrawFailsAsSpectator() public {
    changePrank(p3);
    vm.expectRevert(PlayerOnly.selector);
    engine.respondDraw(gameId, true);
  }

  // Once the timer expires, the responder can no longer accept the draw...
  function testRespondDrawFailsAfterTimeout() public {
    skip(timePerMove+1);
    vm.expectRevert(TimerExpired.selector);
    engine.respondDraw(gameId, true);
  }

  // ...but not before it expires, or a draw offer would be a free win.
  function testClaimVictoryBeforeDrawTimeout() public {
    changePrank(p1);
    assertFalse(engine.timeDidExpire(gameId));
    vm.expectRevert(TimerActive.selector);
    engine.claimVictory(gameId);
  }

  // ...so the offerer must be able to claim the win, or the game (and its
  // escrow) deadlocks in the Draw state forever.
  function testClaimVictoryAfterDrawTimeout() public
    testOutcome(GameOutcome.WhiteWon)
    testWinner(p1)
    testLoser(p2)
    testEarnings(p1, purse())
    testEarnings(p2, 0)
    expectGameOver(p1, p2)
  {
    changePrank(p1);
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    engine.claimVictory(gameId);
  }
}
