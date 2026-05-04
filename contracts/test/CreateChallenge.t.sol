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
    lobby.challenge(p2, true, timePerMove, 0, address(0));
  }

  function testChallengeWithWager() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
    testEarnings(p1, 0)
  {
    lobby.challenge{ value: deposit }(p2, true, timePerMove, wager, address(0));
  }

  function testChallengeSucceedsWithMinTPM() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
  {
    lobby.challenge(p2, true, 60, 0, address(0));
  }

  function testChallengeFailsWithInvalidTPM() public {
    vm.expectRevert(ChessEngine.InvalidTimePerMove.selector);
    lobby.challenge(p2, true, 59, 0, address(0));
  }

  function testChallengeFailsWithNoDeposit() public {
    vm.expectRevert(ChessEngine.InvalidDepositAmount.selector);
    lobby.challenge(p2, true, timePerMove, wager, address(0));
  }

  function testChallengeFailsWithLowDeposit() public {
    vm.expectRevert(ChessEngine.InvalidDepositAmount.selector);
    lobby.challenge{ value: deposit-1 }(p2, true, timePerMove, wager, address(0));
  }

  function testChallengeSucceedsWithExcessDeposit() public
    testChallengeSent(0, p1)
    testChallengeReceived(0, p2)
    testEarnings(p1, 0)
  {
    lobby.challenge{ value: deposit+1 }(p2, true, timePerMove, wager, address(0));
  }
}
