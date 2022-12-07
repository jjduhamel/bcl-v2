// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract DrawGameTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    changePrank(p1);
    engine.offerDraw(gameId);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Draw));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    changePrank(p2);
  }

  function testMoveFailsDuringDraw() public {
    vm.expectRevert('InvalidContractState');
    _move(p2, 'b6');
  }

  function testAcceptDraw() public
    testOutcome(GameOutcome.Draw)
    testDraw(p1)
    testDraw(p2)
    testBalanceDelta(p1, int(wager))
    testBalanceDelta(p2, int(wager))
  {
    engine.respondDraw(gameId, true);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Finished));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Draw));
  }

  function testDeclineDraw() public
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, 0)
  {
    engine.respondDraw(gameId, false);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Started));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    _testMove(p1, 'a3');
    _testMove(p2, 'b6');
  }

  function testRespondDrawFailsAsSender() public {
    changePrank(p1);
    vm.expectRevert('NotCurrentMove');
    engine.respondDraw(gameId, true);
  }

  function testRespondDrawFailsAsSpectator() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.respondDraw(gameId, true);
  }
}
