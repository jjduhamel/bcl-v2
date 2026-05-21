// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './Challenge.t.sol';

contract AcceptChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: wager }(p2, true, timePerMove, wager, address(0));
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
    lobby.acceptChallenge{ value: wager }(gameId);
  }

  function testAcceptFailsWithoutDeposit() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.acceptChallenge(gameId);
  }

  function testAcceptFailsWithLowDeposit() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.acceptChallenge{ value: wager-1 }(gameId);
  }

  function testAcceptRevertsOnExcessDeposit() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    lobby.acceptChallenge{ value: wager+1 }(gameId);
  }

  function testAcceptFailsAsSender() public {
    changePrank(p1);
    vm.expectRevert(NotCurrentMove.selector);
    lobby.acceptChallenge{ value: wager }(gameId);
  }

  function testAcceptAsSpectator() public {
    changePrank(p3);
    vm.expectRevert(PlayerOnly.selector);
    lobby.acceptChallenge{ value: wager }(gameId);
  }

  function testAcceptDisbursesExcessFunds() public
    testChallengeAccepted(gameId, p1)
    testChallengeAccepted(gameId, p2)
    testGameStarted(gameId, p1)
    testGameStarted(gameId, p2)
    // NOTE: Modifying the challenge will also change the platform fee
    //       that the contract computes, so the earnings will be in 
    //       excess of wager amount.
    testEarnings(p1, wager/2)
  {
    lobby.modifyChallenge{ value: wager/2 }
                          (gameId, true, timePerMove, wager/2);
    changePrank(p1);
    // We need to do this here because otherwise modifyChallenge throws a touch event 
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameStarted(gameId, p2, p1);
    lobby.acceptChallenge(gameId);
  }

  function testAcceptFailsAfterAccept() public {
    lobby.acceptChallenge{ value: wager }(gameId);
    vm.expectRevert(InvalidContractState.selector);
    lobby.acceptChallenge(gameId);
  }

  function testDeclineFailsAfterAccept() public {
    lobby.acceptChallenge{ value: wager }(gameId);
    vm.expectRevert(InvalidContractState.selector);
    lobby.declineChallenge(gameId);
  }

  function testModifyFailsAfterAccept() public {
    lobby.acceptChallenge{ value: wager }(gameId);
    vm.expectRevert(InvalidContractState.selector);
    lobby.modifyChallenge(gameId, true, timePerMove, wager);
  }
}
