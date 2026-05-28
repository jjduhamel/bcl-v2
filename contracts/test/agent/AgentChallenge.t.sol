// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '../Challenge.t.sol';

contract AgentChallengeTest is ChallengeTest {
  address a1;  // owned by p1
  address a2;

  function setUp() public {
    a1 = makeAddr('agent1');
    a2 = makeAddr('agent2');
    // Fund the agents so wagered calls exercise the access path, not balance checks.
    vm.deal(a1, 100 ether);
    vm.deal(a2, 100 ether);
    changePrank(p1);
    lobby.registerAgent(a1, 'bot', '', 'Hermes', 'Claude Opus', '4.7');
  }

  function testChallengeSeatsAgent() public {
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, a1, p2);
    uint gid = lobby.challenge{ value: wager }(a1, p2, true, timePerMove, wager, address(0));

    GameData memory g = engine.game(gid);
    assertEq(g.whitePlayer, a1);
    assertEq(g.blackPlayer, p2);

    uint[] memory ca = lobby.challenges(a1);
    uint[] memory cp = lobby.challenges(p2);
    assertEq(ca[ca.length-1], gid);
    assertEq(cp[cp.length-1], gid);

    assertEq(lobby.gameStats(a1).created, 1);
  }

  function testChallengeAsSelf() public {
    uint gid = lobby.challenge{ value: wager }(p1, p2, true, timePerMove, wager, address(0));
    GameData memory g = engine.game(gid);
    assertEq(g.whitePlayer, p1);
  }

  function testChallengeNotOwner() public {
    // a2 is owned by p3, so p1 cannot seat it.
    changePrank(p3);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    vm.expectRevert(NotAgentOwner.selector);
    lobby.challenge{ value: wager }(a2, p2, true, timePerMove, wager, address(0));
  }

  // Only the owner of the seated agent may accept on its behalf — not the agent key,
  // even though it holds enough ETH to cover the wager.
  function testAgentCannotAcceptForOwner() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));

    changePrank(a2);
    vm.expectRevert(PlayerOnly.selector);
    lobby.acceptChallenge{ value: wager }(gid);
  }

  // p1 seats agent a1 against human p2; leaves the prank as p1 (the owner).
  function _challenge() internal returns (uint) {
    changePrank(p1);
    return lobby.challenge{ value: wager }(a1, p2, true, timePerMove, wager, address(0));
  }

  function testAgentCantDeclineChallenge() public {
    uint gid = _challenge();
    changePrank(a1);
    vm.expectRevert(PlayerOnly.selector);
    lobby.declineChallenge(gid);
  }

  function testAgentCantModifyChallenge() public {
    uint gid = _challenge();
    changePrank(a1);
    vm.expectRevert(NotAgentOwner.selector);
    lobby.modifyChallenge(gid, a1, true, timePerMove, wager);
  }

  function testOwnerCanDeclineAgentChallenge() public {
    uint gid = _challenge();
    vm.expectEmit(true, true, true, true, address(lobby));
    emit ChallengeDeclined(gid, a1, p2);
    lobby.declineChallenge(gid);
    // The owner's deposit is refunded to the owner.
    assertEq(lobby.earnings(address(0)), wager);
  }

  function testOwnerCanModifyAgentChallenge() public {
    uint gid = _challenge();
    lobby.modifyChallenge(gid, a1, true, timePerMove + 60, wager);
    GameData memory g = engine.game(gid);
    assertEq(g.timePerMove, timePerMove + 60);
  }

  // The wager is escrowed under the owner, never the agent seat.
  function testChallengeEscrowKeyedToOwner() public {
    uint gid = _challenge();
    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(gid, p1), wager);
    assertEq(lobby.checkPlayerDeposit(gid, a1), 0);
  }

  // An owner of the non-current seat passes isPlayer but fails isCurrentMove.
  function testWrongOwnerCannotAccept() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
    vm.expectRevert(NotCurrentMove.selector);
    lobby.acceptChallenge{ value: wager }(gid);
  }

  function testOwnerModifyUpToppedFromOwner() public {
    uint gid = _challenge();
    lobby.modifyChallenge{ value: wager }(gid, a1, true, timePerMove, wager * 2);
    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(gid, p1), wager * 2);
    assertEq(lobby.checkPlayerDeposit(gid, a1), 0);
  }

  // Decline refunds the owners (p1 and p2), never the agent seats.
  function testDeclineRefundsAgentOpponentOwner() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
    // p2 funds the a2 seat via modify so both owners hold escrow.
    changePrank(p2);
    lobby.modifyChallenge{ value: wager }(gid, a2, false, timePerMove, wager);

    changePrank(p1);
    lobby.declineChallenge(gid);

    changePrank(arbiter);
    assertEq(lobby.checkPlayerEarnings(p1, address(0)), wager);
    assertEq(lobby.checkPlayerEarnings(p2, address(0)), wager);
    assertEq(lobby.checkPlayerEarnings(a1, address(0)), 0);
    assertEq(lobby.checkPlayerEarnings(a2, address(0)), 0);
  }
}
