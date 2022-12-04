// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './Challenge.t.sol';

contract AcceptChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    changePrank(p2);
  }

  modifier testChallengeAccepted(uint gameId, address player) {
    uint[] memory challenges = lobby.challenges(player);
    assertEq(gameId, challenges[challenges.length-1]);
    _;
    uint[] memory games = lobby.games(player);
    assertEq(lobby.challenges(player).length, challenges.length-1);
    assertEq(gameId, games[games.length-1]);
  }

  modifier expectGameStarted(address sender, address receiver) {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameStarted(gameId, sender, receiver);
    _;
  }

  function testAcceptWithDeposit() public
    testChallengeAccepted(gameId, p1)
    testChallengeAccepted(gameId, p2)
    testGameStarted(gameId, p1)
    testGameStarted(gameId, p2)
    expectGameStarted(p1, p2)
  {
    GameData memory gameData = engine.game(gameId);
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testAcceptFailsWithoutDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    engine.acceptChallenge(gameId);
  }

  function testAcceptFailsWithLowDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    engine.acceptChallenge{ value: deposit-1 }(gameId);
  }

  function testAcceptWithExcessDeposit() public
    testChallengeAccepted(gameId, p1)
    testChallengeAccepted(gameId, p2)
    testGameStarted(gameId, p1)
    testGameStarted(gameId, p2)
    testBalanceDelta(p2, -int(deposit))
    expectGameStarted(p1, p2)
  {
    engine.acceptChallenge{ value: deposit+1 }(gameId);
  }

  function testAcceptFailsAsSender() public {
    changePrank(p1);
    vm.expectRevert('NotCurrentMove');
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testAcceptAsSpectator() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testAcceptDisbursesExcessFunds() public
    testChallengeAccepted(gameId, p1)
    testChallengeAccepted(gameId, p2)
    testGameStarted(gameId, p1)
    testGameStarted(gameId, p2)
    testBalanceDelta(p1, int(deposit/2))
    testBalanceDelta(p2, -int(deposit/2))
    expectGameStarted(p2, p1)
  {
    engine.modifyChallenge{ value: wager*2+fee }
                          (gameId, true, timePerMove, wager/2);
    changePrank(p1);
    engine.acceptChallenge(gameId);
  }

  function testAcceptFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.acceptChallenge(gameId);
  }

  function testDeclineFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.declineChallenge(gameId);
  }

  function testModifyFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }
}
