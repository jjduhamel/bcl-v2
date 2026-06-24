// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20PlatformTest is EscrowTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(token));
    _stake(p2, gameId, wager, address(token));
    _chargeFee(p1, gameId, address(token));
    _chargeFee(p2, gameId, address(token));
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(availableFunds(address(0), address(token)), 2 * fee);
  }

  function testWithdrawPlatformTransfersTokens() public {
    address recipient = makeAddr('recipient');
    _releasePlatformFunds(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    _releasePlatformFunds(address(token), recipient);
    assertEq(availableFunds(address(0), address(token)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address recipient = makeAddr('recipient');
    _releasePlatformFunds(address(token), recipient);
    _releasePlatformFunds(address(token), recipient);
    assertEq(token.balanceOf(recipient), 2 * fee);
  }
}

contract EscrowETHPlatformTest is EscrowETHTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(0));
    _stake(p2, gameId, wager, address(0));
    _chargeFee(p1, gameId, address(0));
    _chargeFee(p2, gameId, address(0));
  }

  function testPlatformEarningsAccumulate() public {
    assertEq(availableFunds(address(0), address(0)), 2 * fee);
  }

  function testWithdrawPlatformTransfersETH() public {
    address payable recipient = payable(makeAddr('recipient'));
    uint before = recipient.balance;
    _releasePlatformFunds(address(0), recipient);
    assertEq(recipient.balance, before + 2 * fee);
  }

  function testWithdrawPlatformClearsEarnings() public {
    address recipient = makeAddr('recipient');
    _releasePlatformFunds(address(0), recipient);
    assertEq(availableFunds(address(0), address(0)), 0);
  }

  function testWithdrawPlatformZeroBalanceIsNoop() public {
    address payable recipient = payable(makeAddr('recipient'));
    _releasePlatformFunds(address(0), recipient);
    _releasePlatformFunds(address(0), recipient);
    assertEq(recipient.balance, 2 * fee);
  }
}
