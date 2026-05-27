// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '../Challenge.t.sol';

// End-to-end: two agents play a wagered game; the wager is funded by, and the
// payout accrues to, the human owners — the agent keys never custody funds.
contract AgentGameTest is ChallengeTest {
  address a1;  // owned by p1, seated white
  address a2;  // owned by p2, seated black
  uint gid;

  function setUp() public {
    a1 = makeAddr('agent1');
    a2 = makeAddr('agent2');
    changePrank(p1);
    lobby.registerAgent(a1, 'white-bot', '', 'Hermes', 'Claude Opus', '4.7');
    changePrank(p2);
    lobby.registerAgent(a2, 'black-bot', '', 'Hermes', 'Claude Opus', '4.7');
    changePrank(p1);
    gid = lobby.challenge{ value: wager }(a1, a2, true, timePerMove, wager, address(0));
  }

  function _accept() internal {
    changePrank(p2);
    lobby.acceptChallenge{ value: wager }(gid);
  }

  function testAgentPlaysAndOwnerPaid() public {
    _accept();

    // The agent key drives the game directly via the ChessEngine.
    changePrank(a1);
    engine.move(gid, 'e2e4');
    changePrank(a2);
    engine.resign(gid);

    // White agent wins; stats accrue on the agents.
    assertEq(engine.winner(gid), a1);
    assertEq(lobby.gameStats(a1).won, 1);
    assertEq(lobby.gameStats(a2).lost, 1);

    // Funds route to the owners, not the agents.
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), purse());
    changePrank(a1);
    assertEq(lobby.earnings(address(0)), 0);
    changePrank(p2);
    assertEq(lobby.earnings(address(0)), 0);

    // Owner withdraws the purse; the agent key holds nothing.
    uint ownerBefore = p1.balance;
    uint agentBefore = a1.balance;
    changePrank(p1);
    lobby.withdraw(address(0));
    assertEq(p1.balance, ownerBefore + purse());
    assertEq(a1.balance, agentBefore);
  }

  // netEarnings reports the queried account's net wager P&L, not the caller's.
  function testNetEarnings() public {
    _accept();
    changePrank(a1);
    engine.move(gid, 'e2e4');
    changePrank(a2);
    engine.resign(gid); // a1 wins the wager

    changePrank(p1);
    assertEq(lobby.netEarnings(a1), int(wager));
    changePrank(p2);
    assertEq(lobby.netEarnings(a2), -int(wager));
  }

  // A compromised agent key cannot pull the owner's winnings.
  function testAgentHasNoWithdrawableBalance() public {
    _accept();
    changePrank(a2);
    engine.resign(gid);

    changePrank(a1);
    vm.expectRevert(EscrowContract.InsufficientBalance.selector);
    lobby.withdraw(address(0));
  }

  // BlackWon disburse branch: white resigns → black's owner is paid.
  function testBlackAgentWins() public {
    _accept();
    changePrank(a1);
    engine.resign(gid);
    assertEq(engine.winner(gid), a2);
    assertEq(lobby.gameStats(a2).won, 1);
    assertEq(lobby.gameStats(a1).lost, 1);
    changePrank(p2);
    assertEq(lobby.earnings(address(0)), purse());
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), 0);
  }

  // Draw disburse branch: each owner gets half the purse.
  function testAgentsDraw() public {
    _accept();
    changePrank(a1);
    engine.offerDraw(gid);
    changePrank(a2);
    engine.respondDraw(gid, true);
    assertEq(lobby.gameStats(a1).draws, 1);
    assertEq(lobby.gameStats(a2).draws, 1);
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), purse() / 2);
    changePrank(p2);
    assertEq(lobby.earnings(address(0)), purse() / 2);
  }

  // Agent claims victory on the opponent's timeout; the owner is paid.
  function testAgentClaimsVictoryOnTimeout() public {
    _accept();
    changePrank(a1);
    engine.move(gid, 'e2e4');
    skip(timePerMove + 1);
    engine.claimVictory(gid);
    assertEq(engine.winner(gid), a1);
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), purse());
  }

  // Agent raises a dispute; arbiter resolves; owner is paid.
  function testAgentDisputeResolved() public {
    _accept();
    changePrank(a1);
    engine.move(gid, 'e2e4');
    changePrank(a2);
    vm.expectEmit(true, true, true, true, address(lobby));
    emit GameDisputed(gid, a2, a1);
    engine.disputeGame(gid);
    assertEq(uint(engine.game(gid).state), uint(GameState.Review));

    changePrank(arbiter);
    assertEq(lobby.disputes().length, 1);
    engine.resolveDispute(gid, GameOutcome.WhiteWon);
    assertEq(lobby.disputes().length, 0);

    assertEq(engine.winner(gid), a1);
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), purse());
  }

  // One owner may run both seats (wager-free); play and stats work per agent.
  function testSameOwnerBothAgents() public {
    address b1 = makeAddr('b1');
    address b2 = makeAddr('b2');
    changePrank(p1);
    lobby.registerAgent(b1, 'b1', '', '', '', '');
    lobby.registerAgent(b2, 'b2', '', '', '', '');
    uint g = lobby.challenge(b1, b2, true, timePerMove, 0, address(0));
    lobby.acceptChallenge(g);
    changePrank(b2);
    engine.resign(g);
    assertEq(engine.winner(g), b1);
    assertEq(lobby.gameStats(b1).won, 1);
    assertEq(lobby.gameStats(b2).lost, 1);
  }

  function testCannotUnregisterDuringGame() public {
    _accept();
    changePrank(p1);
    vm.expectRevert(AgentInGame.selector);
    lobby.unregisterAgent(a1);
  }

  function testCanUnregisterAfterGame() public {
    _accept();
    changePrank(a2);
    engine.resign(gid);
    changePrank(p1);
    lobby.unregisterAgent(a1);
    assertEq(lobby.agents(p1).length, 0);
  }
}
