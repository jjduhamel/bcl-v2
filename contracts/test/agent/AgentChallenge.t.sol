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

  // Agents never custody funds — the deposit surface is for players (owners) only.
  function testAgentCannotDeposit() public {
    changePrank(a1);
    vm.expectRevert(Unauthorized.selector);
    lobby.deposit{ value: 1 ether }(1 ether, address(0));
  }

  function testChallengeSeatsAgent() public {
    changePrank(p2);
    lobby.registerAgent{ value: wager }(a2, 'bot', '', '', '', '');  // fund p2 so a2 can be challenged for a wager
    changePrank(p1);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, a1, a2);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));

    GameData memory g = engine.game(gid);
    assertEq(g.whitePlayer, a1);
    assertEq(g.blackPlayer, a2);

    uint[] memory ca = lobby.challenges(a1);
    uint[] memory cp = lobby.challenges(a2);
    assertEq(ca[ca.length-1], gid);
    assertEq(cp[cp.length-1], gid);

    assertEq(lobby.gameStats(a1).created, 1);
  }

  // An agent sends a directed challenge for its own seat — but only to another agent.
  function testAgentChallengesAgentAsSelf() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(a1);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, a1, a2);
    uint gid = lobby.challenge(a1, a2, true, timePerMove, 0, address(0));
    assertEq(engine.game(gid).whitePlayer, a1);
    assertEq(engine.game(gid).blackPlayer, a2);
  }

  // An agent may not challenge a human player — neither acting for itself...
  function testAgentCannotChallengePlayerAsSelf() public {
    changePrank(a1);
    vm.expectRevert(Unauthorized.selector);
    lobby.challenge(a1, p2, true, timePerMove, 0, address(0));
  }

  // ...nor when its owner sends the challenge on its behalf (the rule is relationship-based).
  function testAgentCannotChallengePlayerAsOwner() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    lobby.challenge{ value: wager }(a1, p2, true, timePerMove, wager, address(0));
  }

  // One-way: a human player may still challenge an agent.
  function testPlayerCanChallengeAgent() public {
    changePrank(p2);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, p2, a1);
    uint gid = lobby.challenge(p2, a1, true, timePerMove, 0, address(0));
    assertEq(engine.game(gid).blackPlayer, a1);
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
    vm.expectRevert(Unauthorized.selector);
    lobby.challenge{ value: wager }(a2, p2, true, timePerMove, wager, address(0));
  }

  // The agent itself accepts (it is the current-move seat), funded from its owner's
  // pre-deposited balance.
  function testAgentAccepts() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    lobby.deposit{ value: wager }(wager, address(0));   // owner p2 funds a2's side
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));

    changePrank(a2);
    lobby.acceptChallenge(gid);
    assertTrue(engine.game(gid).state == IChessEngine.GameState.Started);
  }

  // An agent acts only for its own seat — not for a sibling agent of the same owner.
  function testAgentCannotAcceptForSibling() public {
    address a3 = makeAddr('agent3');
    lobby.registerAgent(a3, 'bot', '', '', '', '');   // p1 owns both a1 and a3
    changePrank(p2);
    uint gid = lobby.challenge(p2, a3, true, timePerMove, 0, address(0));   // a3 is current move
    changePrank(a1);
    vm.expectRevert(Unauthorized.selector);
    lobby.acceptChallenge(gid);
  }

  // ...nor on behalf of its owner's own seat.
  function testAgentCannotAcceptForOwner() public {
    changePrank(p2);
    uint gid = lobby.challenge(p2, p1, true, timePerMove, 0, address(0));   // p1 (owner) is current move
    changePrank(a1);
    vm.expectRevert(Unauthorized.selector);
    lobby.acceptChallenge(gid);
  }

  // p1 seats agent a1 against agent a2 (owned by p2); leaves the prank as p1 (the owner).
  // Agents may only challenge other agents, so the opponent seat is an agent, not human p2.
  function _challenge() internal returns (uint) {
    changePrank(p2);
    lobby.registerAgent{ value: wager }(a2, 'bot', '', '', '', '');  // fund p2 for the opponent-balance check
    changePrank(p1);
    return lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
  }

  function testAgentDeclinesChallenge() public {
    uint gid = _challenge();
    changePrank(a1);
    vm.expectEmit(true, true, true, true, address(lobby));
    emit ChallengeDeclined(gid, a1, a2);
    lobby.declineChallenge(gid);
    // The owner's deposit is refunded to the owner, not the agent seat.
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), wager);
  }

  function testAgentModifiesChallenge() public {
    uint gid = _challenge();
    changePrank(a1);
    lobby.modifyChallenge(gid, a1, true, timePerMove + 60, wager);
    assertEq(engine.game(gid).timePerMove, timePerMove + 60);
  }

  function testOwnerCanDeclineAgentChallenge() public {
    uint gid = _challenge();
    vm.expectEmit(true, true, true, true, address(lobby));
    emit ChallengeDeclined(gid, a1, a2);
    lobby.declineChallenge(gid);
    // The owner's deposit is refunded to the owner.
    assertEq(uint(earnings(address(0))), wager);
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
    lobby.registerAgent{ value: wager }(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
    vm.expectRevert(Unauthorized.selector);
    lobby.acceptChallenge{ value: wager }(gid);
  }

  function testOwnerModifyUpToppedFromOwner() public {
    uint gid = _challenge();
    changePrank(p2);
    lobby.deposit{ value: wager }(wager, address(0));  // top p2 to wager*2 for the raised opponent check
    changePrank(p1);
    lobby.modifyChallenge{ value: wager }(gid, a1, true, timePerMove, wager * 2);
    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(gid, p1), wager * 2);
    assertEq(lobby.checkPlayerDeposit(gid, a1), 0);
  }

  // Decline refunds the owners (p1 and p2), never the agent seats.
  function testDeclineRefundsAgentOpponentOwner() public {
    changePrank(p2);
    lobby.registerAgent{ value: wager }(a2, 'bot', '', '', '', '');  // p2 deposits its wager up front
    changePrank(p1);
    uint gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
    // p2 escrows the a2 seat from its deposited balance so both owners hold escrow.
    changePrank(p2);
    lobby.modifyChallenge(gid, a2, false, timePerMove, wager);

    changePrank(p1);
    lobby.declineChallenge(gid);

    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), wager);
    assertEq(uint(checkPlayerEarnings(p2, address(0))), wager);
    assertEq(uint(checkPlayerEarnings(a1, address(0))), 0);
    assertEq(uint(checkPlayerEarnings(a2, address(0))), 0);
  }

  // --- Agent acts on the Lobby for itself; the wager is funded from the owner ---

  function testAgentCreatesTable() public {
    changePrank(p1);
    lobby.deposit{ value: wager }(wager, address(0));   // owner funds the open-table wager
    changePrank(a1);
    uint gid = lobby.createTable(a1, true, timePerMove, wager, address(0));
    assertEq(engine.game(gid).whitePlayer, a1);
    // Wager escrowed under the owner, not the agent seat.
    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(gid, p1), wager);
    assertEq(lobby.checkPlayerDeposit(gid, a1), 0);
  }

  function testAgentJoinsTable() public {
    changePrank(p2);
    uint gid = lobby.createTable(p2, true, timePerMove, 0, address(0));
    changePrank(a1);
    lobby.joinTable(gid, a1);
    assertEq(engine.game(gid).blackPlayer, a1);
  }

  function testAgentRevokesTable() public {
    changePrank(p1);
    lobby.deposit{ value: wager }(wager, address(0));
    changePrank(a1);
    uint gid = lobby.createTable(a1, true, timePerMove, wager, address(0));
    lobby.closeTable(gid);
    // The owner's locked wager is released back to its available balance.
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), wager);
    assertEq(lobby.checkPlayerDeposit(gid, p1), 0);
  }

  // An agent can't be challenged for a wager its owner hasn't funded — caught at creation,
  // since _create checks the opponent's available balance.
  function testChallengeRevertsWhenOpponentUnderfunded() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');  // p2 holds no balance
    changePrank(p1);
    vm.expectRevert(InvalidWager.selector);
    lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
  }

  /*
   * Suspended agents take no new engagements — only complete in-progress games.
   */

  // A suspended agent can't initiate a new challenge.
  function testSuspendedAgentCannotChallenge() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    lobby.suspendAgent(a1);
    vm.expectRevert(Forbidden.selector);
    lobby.challenge(a1, a2, true, timePerMove, 0, address(0));
  }

  // ...and can't be the target of a new challenge (block all sides).
  function testCannotChallengeSuspendedOpponent() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    lobby.suspendAgent(a2);            // p2 owns a2
    changePrank(p1);
    vm.expectRevert(Forbidden.selector);
    lobby.challenge(a1, a2, true, timePerMove, 0, address(0));
  }

  // A suspended agent can't open a new table.
  function testSuspendedAgentCannotCreateTable() public {
    changePrank(p1);
    lobby.suspendAgent(a1);
    vm.expectRevert(Forbidden.selector);
    lobby.createTable(a1, true, timePerMove, 0, address(0));
  }

  // A suspended agent can't accept a challenge into a new game.
  function testSuspendedAgentCannotAccept() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge(a1, a2, true, timePerMove, 0, address(0));  // a2's turn to accept
    changePrank(p2);
    lobby.suspendAgent(a2);
    vm.expectRevert(Forbidden.selector);
    lobby.acceptChallenge(gid);
  }

  // Exiting a pending challenge is allowed while suspended (don't trap the owner's escrow).
  function testSuspendedAgentCanDecline() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    uint gid = lobby.challenge(a1, a2, true, timePerMove, 0, address(0));
    changePrank(p2);
    lobby.suspendAgent(a2);
    lobby.declineChallenge(gid);       // must not revert
    assertEq(lobby.challenges(a2).length, 0);
  }

  // Resuming restores the ability to take new engagements.
  function testResumeRestoresChallengeability() public {
    changePrank(p2);
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(p1);
    lobby.suspendAgent(a1);
    lobby.resumeAgent(a1);
    uint gid = lobby.challenge(a1, a2, true, timePerMove, 0, address(0));
    assertEq(engine.game(gid).whitePlayer, a1);
  }
}
