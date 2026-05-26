// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Test.sol';
import '../Lobby.t.sol';
import '@aa/core/EntryPoint.sol';
import '@aa/core/BaseAccount.sol';
import '@aa/accounts/Simple7702Account.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/interfaces/PackedUserOperation.sol';

// End-to-end: a delegated agent EOA plays a move via the EntryPoint, holding no ETH; the Lobby
// paymaster sponsors the gas.
contract AgentGaslessTest is LobbyTest {
  address constant ENTRYPOINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

  IEntryPoint ep;
  Simple7702Account impl;
  address a1;
  uint256 a1Pk;
  address relayer;
  uint gid;

  function setUp() public {
    EntryPoint deployed = new EntryPoint();
    vm.etch(ENTRYPOINT_V8, address(deployed).code);
    ep = IEntryPoint(ENTRYPOINT_V8);
    impl = new Simple7702Account();

    vm.deal(arbiter, 10 ether);
    lobby.setEntryPoint(ep);
    lobby.depositToEntryPoint{ value: 1 ether }();
    lobby.allowChallenges(true);

    (a1, a1Pk) = makeAddrAndKey('agent'); // holds 0 ETH
    changePrank(p1);
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    gid = lobby.challenge(a1, p2, true, timePerMove, 0, address(0));
    changePrank(p2);
    lobby.acceptChallenge(gid);

    relayer = makeAddr('relayer');
    vm.deal(relayer, 10 ether);

    // Real EIP-7702 authorization signed by the agent key. The cheatcode designates the *next* call
    // as the 7702 tx, so a trivial call into the account applies the delegation.
    changePrank(relayer);
    vm.signAndAttachDelegation(address(impl), a1Pk);
    (bool delegated, ) = a1.call('');
    assertTrue(delegated);
  }

  function testSignDelegationStampsTheDesignator() public view {
    assertEq(a1.code, bytes.concat(hex'ef0100', abi.encodePacked(address(impl))));
  }

  function _pack(uint hi, uint lo) internal pure returns (bytes32) {
    return bytes32((hi << 128) | lo);
  }

  function _signedOp(address target, bytes memory inner)
    internal returns (PackedUserOperation[] memory ops)
  {
    PackedUserOperation memory op;
    op.sender = a1;
    op.nonce = ep.getNonce(a1, 0);
    op.callData = abi.encodeCall(BaseAccount.execute, (target, 0, inner));
    op.accountGasLimits = _pack(2_000_000, 2_000_000);
    op.preVerificationGas = 200_000;
    op.gasFees = _pack(1 gwei, 2 gwei);
    op.paymasterAndData = abi.encodePacked(address(lobby), uint128(1_000_000), uint128(200_000));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(a1Pk, ep.getUserOpHash(op));
    op.signature = abi.encodePacked(r, s, v);
    ops = new PackedUserOperation[](1);
    ops[0] = op;
  }

  function testGaslessMove() public {
    uint256 depositBefore = ep.balanceOf(address(lobby));
    changePrank(relayer);
    ep.handleOps(_signedOp(address(engine), abi.encodeCall(ChessEngine.move, (gid, 'e2e4'))), payable(relayer));

    string[] memory moves = engine.moves(gid);
    assertEq(moves.length, 1);
    assertEq(moves[0], 'e2e4');
    assertEq(a1.balance, 0);
    assertLt(ep.balanceOf(address(lobby)), depositBefore);
  }

  // Phase 1: the platform deposit pays; the owner is not charged.
  function testOwnerIsNotChargedForSponsoredMove() public {
    uint256 ownerBalanceBefore = p1.balance;
    PackedUserOperation[] memory ops = _signedOp(address(engine), abi.encodeCall(ChessEngine.move, (gid, 'e2e4')));
    changePrank(relayer);
    ep.handleOps(ops, payable(relayer));
    assertEq(p1.balance, ownerBalanceBefore);
    changePrank(p1);
    assertEq(lobby.earnings(address(0)), 0);
  }

  // Validation passes but the inner move reverts (bad UCI): the op is still sponsored.
  function testSponsorsButDoesNotApplyARevertingMove() public {
    uint256 depositBefore = ep.balanceOf(address(lobby));
    PackedUserOperation[] memory ops = _signedOp(address(engine), abi.encodeCall(ChessEngine.move, (gid, 'zz')));
    changePrank(relayer);
    ep.handleOps(ops, payable(relayer)); // does not revert
    assertEq(engine.moves(gid).length, 0);
    assertLt(ep.balanceOf(address(lobby)), depositBefore);
  }

  function testRejectsWhenPaymasterDepositTooLow() public {
    changePrank(arbiter);
    lobby.withdrawEntryPointDeposit(ep.balanceOf(address(lobby)), payable(arbiter));
    PackedUserOperation[] memory ops = _signedOp(address(engine), abi.encodeCall(ChessEngine.move, (gid, 'e2e4')));
    changePrank(relayer);
    vm.expectRevert();
    ep.handleOps(ops, payable(relayer));
  }

  function testRejectsNonWhitelistedSelector() public {
    PackedUserOperation[] memory ops =
      _signedOp(address(engine), abi.encodeWithSelector(ChessEngine.startGame.selector, gid));
    changePrank(relayer);
    vm.expectRevert();
    ep.handleOps(ops, payable(relayer));
  }

  function testRejectsNonEngineTarget() public {
    PackedUserOperation[] memory ops =
      _signedOp(address(lobby), abi.encodeWithSelector(Lobby.withdraw.selector, address(0)));
    changePrank(relayer);
    vm.expectRevert();
    ep.handleOps(ops, payable(relayer));
  }
}
