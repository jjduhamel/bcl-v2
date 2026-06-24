// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20DepositTest is EscrowTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(token));
  }

  function testTransfersTokensToContract() public {
    assertEq(token.balanceOf(address(this)), wager);
    assertEq(token.balanceOf(p1), 1000 ether - wager);
  }

  function testUpdatesEscrowBalance() public {
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager);
  }

  function testDoubleDepositAccumulates() public {
    _stake(p1, gameId, wager, address(token));
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, 2 * wager);
  }

  function testWrongTokenReverts() public {
    MockERC20Token token2 = new MockERC20Token();
    token2.mint(p1, wager);
    vm.prank(p1);
    token2.approve(address(this), type(uint256).max);
    _fund(p1, wager, address(token2));
    vm.expectRevert(EscrowLib.InvalidToken.selector);
    _lock(p1, gameId, wager, address(token2));
  }

  function testAmountOverflowReverts() public {
    uint overflow = uint(type(uint96).max) + 1;
    token.mint(p1, overflow);
    _fund(p1, overflow, address(token));
    vm.expectRevert(EscrowLib.AmountOverflow.selector);
    _lock(p1, gameId, overflow, address(token));
  }

  function testDepositAtMaxAmountSucceeds() public {
    uint remaining = uint(type(uint96).max) - wager;
    token.mint(p1, remaining);
    _stake(p1, gameId, remaining, address(token));
    assertEq(currentDeposit(p1, gameId).amount, type(uint96).max);
  }

  function testRefundMovesToEarnings() public {
    _refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(uint(unlockedBalance(p1, address(token))), wager);
  }

  // setUp staked p1's whole balance, so __available pruned the key (0 withdrawable). tokenDeposits() must
  // still surface the token from __restricted.
  function testTokensIncludesFullyLockedToken() public {
    assertEq(uint(unlockedBalance(p1, address(token))), 0);
    address[] memory t = tokenDeposits(p1);
    assertEq(t.length, 1);
    assertEq(t[0], address(token));
  }

  // Once nothing is held (refunded back to available, then withdrawn), both keys are pruned.
  function testTokensEmptyWhenNoBalance() public {
    _refund(p1, gameId);
    _withdraw(p1, address(token));
    assertEq(tokenDeposits(p1).length, 0);
  }

  function testRefundOnZeroIsNoop() public {
    _refund(p2, gameId);
    assertEq(uint(unlockedBalance(p2, address(token))), 0);
    assertEq(tokenDeposits(p2).length, 0);
  }

  function testRefundExcessTrimsOverage() public {
    uint expected = wager / 2;
    _refundExcess(p1, gameId, expected);
    assertEq(currentDeposit(p1, gameId).amount, expected);
    assertEq(uint(unlockedBalance(p1, address(token))), wager - expected);
  }

  function testRefundExcessNoopWhenAtExpected() public {
    _refundExcess(p1, gameId, wager);
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(uint(unlockedBalance(p1, address(token))), 0);
  }

  function testRefundExcessNoopWhenUnderExpected() public {
    _refundExcess(p1, gameId, wager + 1);
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(uint(unlockedBalance(p1, address(token))), 0);
  }

  function testRefundExcessNoopWhenNoDeposit() public {
    _refundExcess(p2, gameId, wager);
    assertEq(uint(unlockedBalance(p2, address(token))), 0);
  }
}

contract EscrowETHDepositTest is EscrowETHTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(0));
  }

  function testUpdatesEscrowBalance() public {
    assertEq(currentDeposit(p1, gameId).token, address(0));
    assertEq(currentDeposit(p1, gameId).amount, wager);
  }

  function testDoubleDepositAccumulates() public {
    _stake(p1, gameId, wager, address(0));
    assertEq(currentDeposit(p1, gameId).amount, 2 * wager);
  }

  function testInsufficientValueReverts() public {
    vm.deal(p2, wager);
    vm.prank(p2);
    vm.expectRevert(EscrowLib.InvalidDeposit.selector);
    this.ext_deposit{value: wager - 1}(p2, wager, address(0));
  }

  function testRefundMovesToEarnings() public {
    _refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(uint(unlockedBalance(p1, address(0))), wager);
  }

  function testRefundOnZeroIsNoop() public {
    _refund(p2, gameId);
    assertEq(uint(unlockedBalance(p2, address(0))), 0);
    assertEq(tokenDeposits(p2).length, 0);
  }
}

// _escrow caller semantics: a non-player caller — an agent acting against its owner's account —
// may only lock what is already available. (Bringing new ETH in is the Lobby's job, via
// _handleETHDeposit, not _escrow's.)
contract EscrowFundETHTest is EscrowETHTest {
  function testNonPlayerLocksFromAvailable() public {
    _fund(p1, wager, address(0));
    this.ext_escrow(p1, gameId, wager, address(0));
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(uint(unlockedBalance(p1, address(0))), 0);
  }

  function testNonPlayerInsufficientAvailableReverts() public {
    vm.expectRevert(EscrowLib.InsufficientBalance.selector);
    this.ext_escrow(p1, gameId, wager, address(0));
  }
}

contract EscrowFundERC20Test is EscrowTest {
  function testPlayerPullsRemainder() public {
    vm.prank(p1);
    this.ext_escrow(p1, gameId, wager, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(token.balanceOf(p1), 1000 ether - wager);
  }

  function testNonPlayerLocksFromAvailable() public {
    _fund(p1, wager, address(token));
    this.ext_escrow(p1, gameId, wager, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(uint(unlockedBalance(p1, address(token))), 0);
  }

  function testNonPlayerDoesNotPull() public {
    vm.expectRevert(EscrowLib.InsufficientBalance.selector);
    this.ext_escrow(p1, gameId, wager, address(token));
    assertEq(token.balanceOf(p1), 1000 ether);
  }
}

contract EscrowMultiGameTest is EscrowTest {
  uint gameId2 = gameId + 1;

  function setUp() public {
    _stake(p1, gameId, wager, address(token));
    _stake(p1, gameId2, wager, address(token));
  }

  function testBalancesAreIndependent() public {
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(currentDeposit(p1, gameId2).token, address(token));
    assertEq(currentDeposit(p1, gameId2).amount, wager);
  }

  function testRefundOneGamePreservesOther() public {
    _refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(currentDeposit(p1, gameId2).amount, wager);
  }

  function testRefundBothGamesAccumulatesEarnings() public {
    _refund(p1, gameId);
    _refund(p1, gameId2);
    assertEq(uint(unlockedBalance(p1, address(token))), 2 * wager);
  }
}
