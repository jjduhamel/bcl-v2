// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './Challenge.t.sol';

contract DeclineChallengeTest is ChallengeTest {
  function setUp() public {
    changePrank(p1);
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    changePrank(p2);
  }

  modifier testChallengeDeclined(uint gameId, address player) {
    uint[] memory challenges = lobby.challenges(player);
    uint[] memory games = lobby.games(player);
    uint[] memory history = lobby.history(player);
    assertEq(gameId, challenges[challenges.length-1]);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Declined);
    assertEq(lobby.challenges(player).length, challenges.length-1);
    assertEq(lobby.games(player).length, games.length);
    assertEq(lobby.history(player).length, history.length);
  }

  modifier expectDeclinedEvent(address sender, address receiver) {
    vm.expectEmit(false, true, true, true, address(lobby));
    emit ChallengeDeclined(0, sender, receiver);
    _;
  }

  function testDeclineAsSender() public
    testChallengeDeclined(gameId, p1)
    testChallengeDeclined(gameId, p2)
    expectDeclinedEvent(p1, p2)
    testBalanceDelta(p1, int(deposit))
    testBalanceDelta(p2, 0)
  {
    changePrank(p1);
    engine.declineChallenge(gameId);
  }

  function testDeclineAsReceiver() public
    testChallengeDeclined(gameId, p1)
    testChallengeDeclined(gameId, p2)
    expectDeclinedEvent(p2, p1)
    testBalanceDelta(p1, int(deposit))
    testBalanceDelta(p2, 0)
  {
    changePrank(p2);
    engine.declineChallenge(gameId);
  }

  function testDeclineAsSpectator() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.declineChallenge(gameId);
  }

  function testAcceptFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.acceptChallenge(gameId);
  }

  function testDeclineFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.declineChallenge(gameId);
  }

  function testModifyFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }
}
