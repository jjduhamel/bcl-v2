// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20FeeTest is EscrowTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(token));
    _stake(p2, gameId, wager, address(token));
  }

  function testChargeFeeDeductsFromEscrow() public {
    _chargeFee(p1, gameId, address(token));
    assertEq(currentDeposit(p1, gameId).token, address(token));
    assertEq(currentDeposit(p1, gameId).amount, wager - fee);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    _chargeFee(p1, gameId, address(token));
    assertEq(availableBalance(address(0), address(token)), fee);
  }

  function testChargeFeeBothPlayers() public {
    _chargeFee(p1, gameId, address(token));
    _chargeFee(p2, gameId, address(token));
    assertEq(availableBalance(address(0), address(token)), 2 * fee);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    _chargeFee(p1, noWagerGame, address(token));
    assertEq(availableBalance(address(0), address(token)), 0);
    assertEq(currentDeposit(p1, noWagerGame).amount, 0);
  }
}

contract EscrowETHFeeTest is EscrowETHTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(0));
    _stake(p2, gameId, wager, address(0));
  }

  function testChargeFeeDeductsFromEscrow() public {
    _chargeFee(p1, gameId, address(0));
    assertEq(currentDeposit(p1, gameId).token, address(0));
    assertEq(currentDeposit(p1, gameId).amount, wager - fee);
  }

  function testChargeFeeAddsToPlatformEarnings() public {
    _chargeFee(p1, gameId, address(0));
    assertEq(availableBalance(address(0), address(0)), fee);
  }

  function testChargeFeeBothPlayers() public {
    _chargeFee(p1, gameId, address(0));
    _chargeFee(p2, gameId, address(0));
    assertEq(availableBalance(address(0), address(0)), 2 * fee);
  }

  function testChargeFeeZeroWagerIsNoop() public {
    uint noWagerGame = gameId + 99;
    _chargeFee(p1, noWagerGame, address(0));
    assertEq(availableBalance(address(0), address(0)), 0);
    assertEq(currentDeposit(p1, noWagerGame).amount, 0);
  }
}
