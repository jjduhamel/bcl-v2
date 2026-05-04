// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20WithdrawTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager);
    deposit(p2, gameId, address(token), wager);
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
  }

  function testTransfersTokensToPlayer() public {
    uint before = token.balanceOf(p1);
    withdraw(p1, address(token));
    assertEq(token.balanceOf(p1), before + 2 * wager);
  }

  function testClearsEarnings() public {
    withdraw(p1, address(token));
    assertEq(earnings(p1, address(token)), 0);
  }

  function testZeroEarningsReverts() public {
    vm.expectRevert('InsufficientBalance');
    withdraw(p2, address(token));
  }
}

contract EscrowETHWithdrawTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    this.depositETH{value: wager}(p2, gameId, address(0), wager);
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
  }

  function testTransfersETHToPlayer() public {
    uint before = p1.balance;
    withdraw(p1, address(0));
    assertEq(p1.balance, before + 2 * wager);
  }

  function testClearsEarnings() public {
    withdraw(p1, address(0));
    assertEq(earnings(p1, address(0)), 0);
  }

  function testZeroEarningsReverts() public {
    vm.expectRevert('InsufficientBalance');
    withdraw(p2, address(0));
  }
}
