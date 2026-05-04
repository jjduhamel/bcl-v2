// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20FeeTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager + fee);
    deposit(p2, gameId, address(token), wager + fee);
  }

  function testChargeFeeDeductsFromEscrow() public {
    chargeFee(p1, gameId, address(token), fee);
    assertEq(escrow(p1, gameId).token, address(token));
    assertEq(escrow(p1, gameId).amount, wager);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFee(p1, gameId, address(token), fee);
    assertEq(earnings(address(0), address(token)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFee(p1, gameId, address(token), fee);
    chargeFee(p2, gameId, address(token), fee);
    assertEq(earnings(address(0), address(token)), 2 * fee);
  }

  function testFeeExceedsBalanceReverts() public {
    vm.expectRevert('InsufficientFunds');
    chargeFee(p1, gameId, address(token), wager + fee + 1);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    chargeFee(p1, noWagerGame, address(token), fee);
    assertEq(earnings(address(0), address(token)), 0);
    assertEq(escrow(p1, noWagerGame).amount, 0);
  }
}

contract EscrowETHFeeTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager + fee}(p1, gameId, address(0), wager+fee);
    this.depositETH{value: wager + fee}(p2, gameId, address(0), wager+fee);
  }

  function testChargeFeeDeductsFromEscrow() public {
    chargeFee(p1, gameId, address(0), fee);
    assertEq(escrow(p1, gameId).token, address(0));
    assertEq(escrow(p1, gameId).amount, wager);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFee(p1, gameId, address(0), fee);
    assertEq(earnings(address(0), address(0)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFee(p1, gameId, address(0), fee);
    chargeFee(p2, gameId, address(0), fee);
    assertEq(earnings(address(0), address(0)), 2 * fee);
  }

  function testFeeExceedsBalanceReverts() public {
    vm.expectRevert('InsufficientFunds');
    chargeFee(p1, gameId, address(0), wager + fee + 1);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    chargeFee(p1, noWagerGame, address(0), fee);
    assertEq(earnings(address(0), address(0)), 0);
    assertEq(escrow(p1, noWagerGame).amount, 0);
  }
}
