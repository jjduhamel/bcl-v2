// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/IChessEngine.sol';
import './Challenge.t.sol';

contract ModifyChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: wager }(p1, p2, true, timePerMove, wager, address(0));
    changePrank(p2);
  }

  modifier expectTouchRecord(uint gameId, address sender, address receiver) {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit TouchRecord(gameId, sender, receiver);
    _;
  }

  function testModifyColor() public
    expectTouchRecord(gameId, p2, p1)
  {
    lobby.modifyChallenge{ value: wager }(gameId, p2, true, timePerMove, wager);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyColorAsSender() public
    expectTouchRecord(gameId, p1, p2)
  {
    changePrank(p1);
    lobby.modifyChallenge(gameId, p1, false, timePerMove, wager);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == IChessEngine.GameState.Pending);
    assertEq(gameData.currentMove, p2);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyFailsWithoutDeposit() public
  {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.modifyChallenge(gameId, p2, true, timePerMove, wager);
  }

  function testModifyFailsWithLowDeposit() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.modifyChallenge{ value: wager-1 }(gameId, p2, true, timePerMove, wager);
  }

  function testModifyTimePerMove() public
    expectTouchRecord(gameId, p2, p1)
  {
    lobby.modifyChallenge{ value: wager }(gameId, p2, false, timePerMove-1, wager);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.timePerMove, timePerMove-1);
  }

  function testModifyInvalidTPMFails() public {
    vm.expectRevert(InvalidTimePerMove.selector);
    lobby.modifyChallenge{ value: wager }(gameId, p2, false, 59, wager);
  }

  function testModifyWager() public
    expectTouchRecord(gameId, p2, p1)
  {
    lobby.modifyChallenge{ value: wager/2 }(gameId, p2, true, timePerMove, wager/2);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.wagerAmount, wager/2);
  }

  function testIncreaseWagerAsSender() public
    testEarnings(p1, 0)
    testEarnings(p2, 0)
    expectTouchRecord(gameId, p1, p2)
  {
    changePrank(p1);
    lobby.modifyChallenge{ value: wager }(gameId, p1, true, timePerMove, wager*2);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.wagerAmount, wager*2);
  }

  function testModifyWagerFailsWithoutDeposit() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.modifyChallenge(gameId, p2, true, timePerMove, wager*2);
  }

  function testModifyFailsAsSpectator() public {
    changePrank(p3);
    vm.expectRevert(PlayerOnly.selector);
    lobby.modifyChallenge(gameId, p3, false, timePerMove*2, wager/2);
  }

  // A participant can only assign a seat they own; passing the opponent's seat fails isOwner.
  function testCannotReassignOpponentSeat() public {
    changePrank(p1);
    vm.expectRevert(NotAgentOwner.selector);
    lobby.modifyChallenge(gameId, p2, true, timePerMove, wager);
  }
}
