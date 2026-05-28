// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20DepositTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager);
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
    deposit(p1, gameId, address(token), wager);
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, 2 * wager);
  }

  function testWrongTokenReverts() public {
    MockERC20Token token2 = new MockERC20Token();
    token2.mint(p1, wager);
    vm.prank(p1);
    token2.approve(address(this), type(uint256).max);
    vm.expectRevert(Escrow.InvalidToken.selector);
    deposit(p1, gameId, address(token2), wager);
  }

  function testAmountOverflowReverts() public {
    uint overflow = uint(type(uint96).max) + 1;
    token.mint(p1, overflow);
    vm.expectRevert(Escrow.AmountOverflow.selector);
    deposit(p1, gameId, address(token), overflow);
  }

  function testDepositAtMaxAmountSucceeds() public {
    uint remaining = uint(type(uint96).max) - wager;
    token.mint(p1, remaining);
    deposit(p1, gameId, address(token), remaining);
    assertEq(currentDeposit(p1, gameId).amount, type(uint96).max);
  }

  function testRefundMovesToEarnings() public {
    refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(releasedFunds(p1, address(token)), wager);
  }

  function testRefundOnZeroIsNoop() public {
    refund(p2, gameId);
    assertEq(releasedFunds(p2, address(token)), 0);
    assertEq(tokens(p2).length, 0);
  }

  function testRefundExcessTrimsOverage() public {
    uint expected = wager / 2;
    refundExcess(p1, gameId, expected);
    assertEq(currentDeposit(p1, gameId).amount, expected);
    assertEq(releasedFunds(p1, address(token)), wager - expected);
  }

  function testRefundExcessNoopWhenAtExpected() public {
    refundExcess(p1, gameId, wager);
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(releasedFunds(p1, address(token)), 0);
  }

  function testRefundExcessNoopWhenUnderExpected() public {
    refundExcess(p1, gameId, wager + 1);
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(releasedFunds(p1, address(token)), 0);
  }

  function testRefundExcessNoopWhenNoDeposit() public {
    refundExcess(p2, gameId, wager);
    assertEq(releasedFunds(p2, address(token)), 0);
  }
}

contract EscrowETHDepositTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
  }

  function testUpdatesEscrowBalance() public {
    assertEq(currentDeposit(p1, gameId).token, address(0));
    assertEq(currentDeposit(p1, gameId).amount, wager);
  }

  function testDoubleDepositAccumulates() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    assertEq(currentDeposit(p1, gameId).amount, 2 * wager);
  }

  function testInsufficientValueReverts() public {
    vm.expectRevert(Escrow.InvalidDeposit.selector);
    this.depositETH{value: wager - 1}(p2, gameId, address(0), wager);
  }

  function testRefundMovesToEarnings() public {
    refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(releasedFunds(p1, address(0)), wager);
  }

  function testRefundOnZeroIsNoop() public {
    refund(p2, gameId);
    assertEq(releasedFunds(p2, address(0)), 0);
    assertEq(tokens(p2).length, 0);
  }
}

contract EscrowMultiGameTest is EscrowTest {
  uint gameId2 = gameId + 1;

  function setUp() public {
    deposit(p1, gameId, address(token), wager);
    deposit(p1, gameId2, address(token), wager);
  }

  function testBalancesAreIndependent() public {
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager);
    assertEq(currentDeposit(p1, gameId2).token, address(token));
    assertEq(currentDeposit(p1, gameId2).amount, wager);
  }

  function testRefundOneGamePreservesOther() public {
    refund(p1, gameId);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(currentDeposit(p1, gameId2).amount, wager);
  }

  function testRefundBothGamesAccumulatesEarnings() public {
    refund(p1, gameId);
    refund(p1, gameId2);
    assertEq(releasedFunds(p1, address(token)), 2 * wager);
  }
}

contract EscrowCrossTypeDepositTest is EscrowETHTest {
  function testETHDepositThenERC20Reverts() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    vm.expectRevert(Escrow.InvalidToken.selector);
    deposit(p1, gameId, address(token), wager);
  }

  function testERC20DepositThenETHReverts() public {
    deposit(p1, gameId, address(token), wager);
    vm.expectRevert(Escrow.InvalidToken.selector);
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
  }
}
