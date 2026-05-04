// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20PlatformTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager + fee);
    deposit(p2, gameId, address(token), wager + fee);
    chargeFee(p1, gameId, address(token), fee);
    chargeFee(p2, gameId, address(token), fee);
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(earnings(address(0), address(token)), 2 * fee);
  }

  function testWithdrawPlatformTransfersTokens() public {
    address recipient = makeAddr('recipient');
    withdrawPlatform(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    withdrawPlatform(address(token), recipient);
    assertEq(earnings(address(0), address(token)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address recipient = makeAddr('recipient');
    withdrawPlatform(address(token), recipient);
    withdrawPlatform(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }
}

contract EscrowETHPlatformTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager + fee}(p1, gameId, address(0), wager+fee);
    this.depositETH{value: wager + fee}(p2, gameId, address(0), wager+fee);
    chargeFee(p1, gameId, address(0), fee);
    chargeFee(p2, gameId, address(0), fee);
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(earnings(address(0), address(0)), 2 * fee);
  }

  function testWithdrawPlatformTransfersETH() public {
    address payable recipient = payable(makeAddr('recipient'));
    uint before = recipient.balance;
    withdrawPlatform(address(0), recipient);
    assertEq(recipient.balance, before + 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    withdrawPlatform(address(0), recipient);
    assertEq(earnings(address(0), address(0)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address payable recipient = payable(makeAddr('recipient'));
    withdrawPlatform(address(0), recipient);
    withdrawPlatform(address(0), recipient);
    assertEq(recipient.balance, 2 * fee);
  }
}
