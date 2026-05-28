// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20FeeTest is EscrowTest {
  function setUp() public {
    deposit(p1, wager, address(token));
    deposit(p2, wager, address(token));
    lock(p1, gameId, wager, address(token));
    lock(p2, gameId, wager, address(token));
  }

  function testChargeFeeDeductsFromEscrow() public {
    chargeFee(p1, gameId, address(token));
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager - fee);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFee(p1, gameId, address(token));
    assertEq(releasedFunds(address(0), address(token)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFee(p1, gameId, address(token));
    chargeFee(p2, gameId, address(token));
    assertEq(releasedFunds(address(0), address(token)), 2 * fee);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    chargeFee(p1, noWagerGame, address(token));
    assertEq(releasedFunds(address(0), address(token)), 0);
    assertEq(currentDeposit(p1, noWagerGame).amount, 0);
  }
}

contract EscrowETHFeeTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    this.depositETH{value: wager}(p2, gameId, address(0), wager);
  }

  function testChargeFeeDeductsFromEscrow() public {
    chargeFee(p1, gameId, address(0));
    assertEq(currentDeposit(p1, gameId).token, address(0));
    assertEq(currentDeposit(p1, gameId).amount, wager - fee);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    chargeFee(p1, gameId, address(0));
    assertEq(releasedFunds(address(0), address(0)), fee);
  }

  function testChargeFeeBothPlayers() public {
    chargeFee(p1, gameId, address(0));
    chargeFee(p2, gameId, address(0));
    assertEq(releasedFunds(address(0), address(0)), 2 * fee);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    chargeFee(p1, noWagerGame, address(0));
    assertEq(releasedFunds(address(0), address(0)), 0);
    assertEq(currentDeposit(p1, noWagerGame).amount, 0);
  }
}
