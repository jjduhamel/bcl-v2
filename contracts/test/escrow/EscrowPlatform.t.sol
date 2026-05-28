// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20PlatformTest is EscrowTest {
  function setUp() public {
    deposit(p1, wager, address(token));
    deposit(p2, wager, address(token));
    lock(p1, gameId, wager, address(token));
    lock(p2, gameId, wager, address(token));
    chargeFee(p1, gameId, address(token));
    chargeFee(p2, gameId, address(token));
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(availableBalance(address(0), address(token)), 2 * fee);
  }

  function testWithdrawPlatformTransfersTokens() public {
    address recipient = makeAddr('recipient');
    releasePlatformFunds(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    releasePlatformFunds(address(token), recipient);
    assertEq(availableBalance(address(0), address(token)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address recipient = makeAddr('recipient');
    releasePlatformFunds(address(token), recipient);
    releasePlatformFunds(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }
}

contract EscrowETHPlatformTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    this.depositETH{value: wager}(p2, gameId, address(0), wager);
    chargeFee(p1, gameId, address(0));
    chargeFee(p2, gameId, address(0));
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(availableBalance(address(0), address(0)), 2 * fee);
  }

  function testWithdrawPlatformTransfersETH() public {
    address payable recipient = payable(makeAddr('recipient'));
    uint before = recipient.balance;
    releasePlatformFunds(address(0), recipient);
    assertEq(recipient.balance, before + 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    releasePlatformFunds(address(0), recipient);
    assertEq(availableBalance(address(0), address(0)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address payable recipient = payable(makeAddr('recipient'));
    releasePlatformFunds(address(0), recipient);
    releasePlatformFunds(address(0), recipient);
    assertEq(recipient.balance, 2 * fee);
  }
}
