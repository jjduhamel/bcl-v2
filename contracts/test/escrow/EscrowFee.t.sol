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
    chargeFeeERC20(p1, gameId, address(token), fee);
    assertEq(balanceERC20(p1, gameId, address(token)), wager);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFeeERC20(p1, gameId, address(token), fee);
    assertEq(earningsERC20(address(0), address(token)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFeeERC20(p1, gameId, address(token), fee);
    chargeFeeERC20(p2, gameId, address(token), fee);
    assertEq(earningsERC20(address(0), address(token)), 2 * fee);
  }
}

contract EscrowETHFeeTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager + fee}(p1, gameId, address(0), wager+fee);
    this.depositETH{value: wager + fee}(p2, gameId, address(0), wager+fee);
  }

  function testChargeFeeDeductsFromEscrow() public {
    chargeFeeERC20(p1, gameId, address(0), fee);
    assertEq(balanceERC20(p1, gameId, address(0)), wager);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFeeERC20(p1, gameId, address(0), fee);
    assertEq(earningsERC20(address(0), address(0)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFeeERC20(p1, gameId, address(0), fee);
    chargeFeeERC20(p2, gameId, address(0), fee);
    assertEq(earningsERC20(address(0), address(0)), 2 * fee);
  }
}
