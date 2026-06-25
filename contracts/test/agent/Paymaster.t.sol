// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Test.sol';
import '../Lobby.t.sol';
import '@src/Paymaster.sol';
import '@aa/core/EntryPoint.sol';
import '@aa/core/BaseAccount.sol';
import '@aa/interfaces/IPaymaster.sol';
import '@aa/interfaces/PackedUserOperation.sol';

// Unit tests for the ERC-4337 paymaster surface (Subproject 2). These exercise the
// paymaster's own logic only, so a plain (non-canonical) EntryPoint instance is enough — the
// 7702 account + canonical address live in AgentGasless.t.sol.
contract PaymasterTest is LobbyTest {
  EntryPoint ep;
  Paymaster paymaster;
  address a1; // registered agent, owned by p1

  function setUp() public {
    vm.deal(arbiter, 100 ether);     // arbiter == admin; LobbyTest only funds p1/p2/p3
    ep = new EntryPoint();
    paymaster = new Paymaster(lobby, ep);
    lobby.setPaymaster(address(paymaster));
    a1 = makeAddr('agent1');
    changePrank(p1);
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    changePrank(arbiter);
  }

  // Wrap an inner call as Simple7702Account.execute(target, value, inner) calldata.
  function _op(address sender, address target, uint value, bytes memory inner)
    internal pure returns (PackedUserOperation memory op)
  {
    op.sender = sender;
    op.callData = abi.encodeCall(BaseAccount.execute, (target, value, inner));
  }

  // Run validation as the EntryPoint and expect it to reject `op` with `err`.
  function _expectRejected(PackedUserOperation memory op, bytes4 err) internal {
    changePrank(address(ep));
    vm.expectRevert(err);
    paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
  }

  // Sponsoring `execute(target, 0, <selector>)` from the agent must revert with `err`.
  function _expectCallRejected(address target, bytes4 selector, bytes4 err) internal {
    _expectRejected(_op(a1, target, 0, abi.encodeWithSelector(selector)), err);
  }

  // Run validation as the EntryPoint and expect it to sponsor `execute(engine, 0, inner)`.
  function _expectSponsored(bytes memory inner) internal {
    _expectSponsoredCall(address(engine), inner);
  }

  // ...sponsor `execute(target, 0, inner)` for an explicit target (engine or the Lobby itself).
  function _expectSponsoredCall(address target, bytes memory inner) internal {
    changePrank(address(ep));
    (bytes memory context, uint256 validationData) =
      paymaster.validatePaymasterUserOp(_op(a1, target, 0, inner), bytes32(0), 0);
    assertEq(validationData, 0);
    assertEq(context, abi.encode(p1)); // billable owner carried to postOp
  }

  /* ---- onlyEntryPoint guard on the 4337 callbacks ---- */

  function testValidateRevertsWhenCallerIsNotEntryPoint() public {
    PackedUserOperation memory op =
      _op(a1, address(engine), 0, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    changePrank(p1);
    vm.expectRevert(Forbidden.selector);
    paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
  }

  function testPostOpRevertsWhenCallerIsNotEntryPoint() public {
    changePrank(p1);
    vm.expectRevert(Forbidden.selector);
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, '', 0, 0);
  }

  /* ---- validate: sponsors a delegated agent's whitelisted engine calls ---- */

  function testValidateSponsorsEveryWhitelistedEngineCall() public {
    _expectSponsored(abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.resign.selector, uint(0)));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.offerDraw.selector, uint(0)));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.respondDraw.selector, uint(0), true));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.claimVictory.selector, uint(0)));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.disputeGame.selector, uint(0)));
  }

  /* ---- validate: sponsors a delegated agent's whitelisted Lobby actions (target == Lobby) ---- */

  function testValidateSponsorsEveryLobbyAction() public {
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.createTable.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.joinTable.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.acceptChallenge.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.modifyChallenge.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.declineChallenge.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.closeTable.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.updateAgent.selector));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.challenge.selector));
  }

  /* ---- validate: suspension gates new engagements, not gas for in-progress play ---- */

  // A suspended agent holds no ETH, so it must still be sponsored to move/resign/claim and finish
  // a game already underway — otherwise its in-progress games would stall to a timeout forfeit.
  function testValidateStillSponsorsSuspendedAgentInProgressPlay() public {
    changePrank(p1);
    lobby.suspendAgent(a1);
    _expectSponsored(abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.resign.selector, uint(0)));
    _expectSponsored(abi.encodeWithSelector(ChessEngine.claimVictory.selector, uint(0)));
    _expectSponsoredCall(address(lobby), abi.encodeWithSelector(Lobby.declineChallenge.selector));
  }

  // A banned agent gets no sponsorship at all — ban still gates the paymaster.
  function testValidateRejectsBannedAgent() public {
    lobby.grantRole(lobby.BANNED_ROLE(), a1);   // pranked as arbiter (admin) from setUp
    _expectCallRejected(address(engine), ChessEngine.move.selector, UserBanned.selector);
  }

  /* ---- validate: rejects non-whitelisted Lobby selectors and foreign targets ---- */

  function testValidateRejectsNonWhitelistedLobbyActions() public {
    // Right target (the Lobby) but a selector outside the sponsored-lobby whitelist.
    _expectCallRejected(address(lobby), Lobby.withdraw.selector, Forbidden.selector);
    _expectCallRejected(address(lobby), Lobby.registerAgent.selector, Forbidden.selector);
    // an agent must never be sponsored to drain the platform's own EntryPoint deposit
    _expectCallRejected(address(lobby), Paymaster.withdrawEntryPointDeposit.selector, Forbidden.selector);
  }

  function testValidateRejectsForeignTarget() public {
    _expectCallRejected(address(0xBEEF), ChessEngine.move.selector, InvalidRequest.selector);
  }

  /* ---- validate: rejects non-whitelisted engine functions (right target, wrong selector) ---- */

  function testValidateRejectsEveryNonWhitelistedEngineCall() public {
    _expectCallRejected(address(engine), ChessEngine.startGame.selector, Forbidden.selector);
    _expectCallRejected(address(engine), ChessEngine.createChallenge.selector, Forbidden.selector);
    _expectCallRejected(address(engine), ChessEngine.resolveDispute.selector, Forbidden.selector);
    _expectCallRejected(address(engine), ChessEngine.modifyChallenge.selector, Forbidden.selector);
  }

  /* ---- validate: rejects malformed / non-agent / value-bearing ops ---- */

  function testValidateRejectsSenderThatIsNotAnAgent() public {
    _expectRejected(
      _op(p2, address(engine), 0, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4')),
      Unauthorized.selector);
  }

  function testValidateRejectsEthValueTransfer() public {
    _expectRejected(
      _op(a1, address(engine), 1, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4')),
      InvalidRequest.selector);
  }

  function testValidateRejectsCallDataThatIsNotAnExecuteCall() public {
    PackedUserOperation memory op;
    op.sender = a1;
    op.callData = abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'); // not execute(...)
    _expectRejected(op, InvalidRequest.selector);
  }

  function testValidateRejectsTruncatedCallData() public {
    PackedUserOperation memory op;
    op.sender = a1;
    op.callData = hex'b61d27'; // fewer than 4 bytes
    _expectRejected(op, InvalidRequest.selector);
  }

  function testValidateRejectsExecuteWithEmptyInnerCall() public {
    _expectRejected(_op(a1, address(engine), 0, ''), InvalidRequest.selector); // inner has no selector
  }

  /* ---- funding surface is admin-only ---- */

  function testSetPaymasterRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    lobby.setPaymaster(address(paymaster));
  }

  function testLobbyPaymasterGetterReturnsConfiguredPaymaster() public view {
    assertEq(lobby.paymaster(), address(paymaster));
  }

  function testDepositToEntryPointRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    paymaster.depositToEntryPoint{ value: 1 ether }();
  }

  function testAddStakeRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    paymaster.addStake{ value: 1 ether }(1 days);
  }

  function testWithdrawEntryPointDepositRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    paymaster.withdrawEntryPointDeposit(1, payable(p1));
  }

  function testUnlockStakeRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    paymaster.unlockStake();
  }

  function testWithdrawStakeRequiresAdmin() public {
    changePrank(p1);
    vm.expectRevert(Unauthorized.selector);
    paymaster.withdrawStake(payable(p1));
  }

  /* ---- funding moves ETH to/from the EntryPoint (admin == arbiter, the default prank) ---- */

  function testDepositThenWithdrawTracksLobbyEntryPointBalance() public {
    paymaster.depositToEntryPoint{ value: 1 ether }();
    assertEq(paymaster.entryPointDeposit(), 1 ether);
    assertEq(ep.balanceOf(address(paymaster)), 1 ether);

    paymaster.withdrawEntryPointDeposit(0.4 ether, payable(arbiter));
    assertEq(paymaster.entryPointDeposit(), 0.6 ether);
  }

  function testAddStakeLocksStakeForTheLobby() public {
    paymaster.addStake{ value: 1 ether }(1 days);
    IStakeManager.DepositInfo memory info = ep.getDepositInfo(address(paymaster));
    assertEq(info.stake, 1 ether);
    assertTrue(info.staked);
  }

  function testStakeUnlockAndWithdrawReturnsEth() public {
    paymaster.addStake{ value: 1 ether }(1 days);
    paymaster.unlockStake();
    vm.expectRevert(); // not due until the unstake delay elapses
    paymaster.withdrawStake(payable(arbiter));

    skip(1 days + 1);
    uint256 balanceBefore = arbiter.balance;
    paymaster.withdrawStake(payable(arbiter));
    assertEq(arbiter.balance, balanceBefore + 1 ether);
    assertEq(ep.getDepositInfo(address(paymaster)).stake, 0);
  }

  function testEntryPointGetterReturnsConfiguredEntryPoint() public {
    assertEq(address(paymaster.entryPoint()), address(ep));
  }

  /* ---- S1: owner funds the gas pot via registerAgent / deposit ---- */

  function testRegisterAgentPayableCreditsAvailable() public {
    changePrank(p1);
    address a2 = makeAddr('agent2');
    lobby.registerAgent{value: 1 ether}(a2, 'bot', '', '', '', '');
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), 1 ether);
  }

  function testRegisterAgentZeroValueLeavesAvailableAtZero() public view {
    // setUp registered a1 with no value — owner's gas pot stays empty.
    assertEq(uint(checkPlayerEarnings(p1, address(0))), 0);
  }

  function testDepositCreditsOwnerGasBalance() public {
    changePrank(p1);
    lobby.deposit{value: 0.5 ether}(0.5 ether, address(0));
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), 0.5 ether);
  }

  /* ---- S1: validate gates on owner's available balance vs maxCost ---- */

  function testValidateRejectsUnfundedOwner() public {
    PackedUserOperation memory op =
      _op(a1, address(engine), 0, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    changePrank(address(ep));
    vm.expectRevert(EscrowLib.InsufficientBalance.selector);
    paymaster.validatePaymasterUserOp(op, bytes32(0), 1 wei);  // any non-zero maxCost
  }

  function testValidateRejectsOwnerBelowMaxCost() public {
    changePrank(p1);
    lobby.deposit{value: 0.1 ether}(0.1 ether, address(0));
    PackedUserOperation memory op =
      _op(a1, address(engine), 0, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    changePrank(address(ep));
    vm.expectRevert(EscrowLib.InsufficientBalance.selector);
    paymaster.validatePaymasterUserOp(op, bytes32(0), 1 ether);
  }

  function testValidateAllowsOwnerAtExactMaxCost() public {
    // gate is `avail < maxCost + gasFee(maxCost)`; default 10% fee means avail must reach 1.1.
    changePrank(p1);
    lobby.deposit{value: 1.1 ether}(1.1 ether, address(0));
    PackedUserOperation memory op =
      _op(a1, address(engine), 0, abi.encodeWithSelector(ChessEngine.move.selector, uint(0), 'e2e4'));
    changePrank(address(ep));
    (bytes memory context, uint256 validationData) =
      paymaster.validatePaymasterUserOp(op, bytes32(0), 1 ether);
    assertEq(validationData, 0);
    assertEq(context, abi.encode(p1));
  }

  /* ---- S1: postOp debits owner, credits platform pot, never reverts ---- */

  function testPostOpDebitsOwnerCreditsPot() public {
    // charge = cost + gasFee(cost) = 0.1 + 0.01 = 0.11 with default 10% fee
    changePrank(p1);
    lobby.deposit{value: 1 ether}(1 ether, address(0));
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(p1), 0.1 ether, 1 gwei);
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), 0.89 ether);
    assertEq(uint(lobby.platformBalance(address(0))), 0.11 ether);
  }

  function testPostOpBillsOpReverted() public {
    changePrank(p1);
    lobby.deposit{value: 1 ether}(1 ether, address(0));
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opReverted, abi.encode(p1), 0.1 ether, 1 gwei);
    changePrank(arbiter);
    assertEq(uint(checkPlayerEarnings(p1, address(0))), 0.89 ether);
    assertEq(uint(lobby.platformBalance(address(0))), 0.11 ether);
  }

  function testPostOpChargesFullIntoDebtWhenCostExceedsAvailable() public {
    changePrank(p1);
    lobby.deposit{value: 0.05 ether}(0.05 ether, address(0));
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(p1), 1 ether, 1 gwei); // no revert
    changePrank(arbiter);
    // charge = 1 + gasFee(1) = 1.1; owner had 0.05, so 0.05 is realized to the pot and the rest
    // becomes gas debt (negative balance).
    assertEq(checkPlayerEarnings(p1, address(0)), -int(1.05 ether));
    assertEq(uint(lobby.platformBalance(address(0))), 0.05 ether);
  }

  function testPostOpZeroAvailableGoesFullyIntoDebt() public {
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(p1), 1 ether, 1 gwei); // no revert
    changePrank(arbiter);
    assertEq(checkPlayerEarnings(p1, address(0)), -int(1.1 ether));
    assertEq(uint(lobby.platformBalance(address(0))), 0);
  }

  function testGasDebtRecoveredOnNextDeposit() public {
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(p1), 1 ether, 1 gwei); // p1 owes 1.1
    changePrank(p1);
    lobby.deposit{value: 2 ether}(2 ether, address(0));
    changePrank(arbiter);
    // 1.1 of the deposit repays the platform first; 0.9 is left spendable.
    assertEq(checkPlayerEarnings(p1, address(0)), int(0.9 ether));
    assertEq(uint(lobby.platformBalance(address(0))), 1.1 ether);
  }

  function testPlatformPotIsWithdrawableAfterCharge() public {
    // charge = 0.3 + gasFee(0.3) = 0.33 with default 10% fee
    changePrank(p1);
    lobby.deposit{value: 1 ether}(1 ether, address(0));
    changePrank(address(ep));
    paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(p1), 0.3 ether, 1 gwei);
    changePrank(arbiter);
    uint balanceBefore = arbiter.balance;
    lobby.withdrawPlatformFunds(address(0), payable(arbiter));
    assertEq(arbiter.balance, balanceBefore + 0.33 ether);
    assertEq(uint(lobby.platformBalance(address(0))), 0);
  }
}
