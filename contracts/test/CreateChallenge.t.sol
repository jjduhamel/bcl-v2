// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './Challenge.t.sol';

contract CreateChallengeTest is ChallengeTest {
  function testChallengeWithoutWager() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
  {
    lobby.challenge(p2, true, timePerMove, 0);
  }

  function testChallengeWithWager() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
    testBalanceDelta(p1, -int(deposit))
  {
    lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
  }

  function testChallengeSucceedsWithMinTPM() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
  {
    lobby.challenge(p2, true, 60, 0);
  }

  function testChallengeFailsWithInvalidTPM() public {
    vm.expectRevert('InvalidTimePerMove');
    lobby.challenge(p2, true, 59, 0);
  }

  function testChallengeFailsWithNoDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    lobby.challenge(p2, true, timePerMove, wager);
  }

  function testChallengeFailsWithLowDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    lobby.challenge{ value: deposit-1 }(p2, true, timePerMove, wager);
  }

  function testChallengeSucceedsWithExcessDeposit() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
    testBalanceDelta(p1, -int(deposit+1))
  {
    lobby.challenge{ value: deposit+1 }(p2, true, timePerMove, wager);
  }
}
