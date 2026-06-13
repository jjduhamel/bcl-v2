// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20WithdrawTest is EscrowTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(token));
    _stake(p2, gameId, wager, address(token));
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
  }

  function testTransfersTokensToPlayer() public {
    uint before = token.balanceOf(p1);
    _withdraw(p1, address(token));
    assertEq(token.balanceOf(p1), before + 2 * wager);
  }

  function testClearsEarnings() public {
    _withdraw(p1, address(token));
    assertEq(availableBalance(p1, address(token)), 0);
  }

  function testZeroEarningsReverts() public {
    vm.expectRevert(Escrow.InsufficientBalance.selector);
    this.ext_withdraw(p2, address(token));
  }
}

contract EscrowETHWithdrawTest is EscrowETHTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(0));
    _stake(p2, gameId, wager, address(0));
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
  }

  function testTransfersETHToPlayer() public {
    uint before = p1.balance;
    _withdraw(p1, address(0));
    assertEq(p1.balance, before + 2 * wager);
  }

  function testClearsEarnings() public {
    _withdraw(p1, address(0));
    assertEq(availableBalance(p1, address(0)), 0);
  }

  function testZeroEarningsReverts() public {
    vm.expectRevert(Escrow.InsufficientBalance.selector);
    this.ext_withdraw(p2, address(0));
  }
}

// Re-enters withdraw from its `receive()` hook. Swallows the reentered revert so
// the outer transfer succeeds — what we care about is that the attacker can't
// observe a stale available balance and drain twice.
contract ReentrantWithdrawer {
  EscrowETHTest internal target;
  uint internal attempts;
  constructor(EscrowETHTest t) { target = t; }
  receive() external payable {
    if (attempts++ < 1) {
      try target.ext_withdraw(address(this), address(0)) {} catch {}
    }
  }
}

// Pinned by the CEI fix in EscrowWrapper.withdraw: state updates happen before the
// external transfer, so a reentrant receiver sees a zero available balance.
contract EscrowReentrancyTest is EscrowETHTest {
  ReentrantWithdrawer atk;

  function setUp() public {
    atk = new ReentrantWithdrawer(this);
    // Fund the attacker's __available slot with one wager's worth.
    _fund(address(atk), wager, address(0));
  }

  function testReentrantWithdrawCannotDoubleSpend() public {
    _withdraw(address(atk), address(0));
    assertEq(address(atk).balance, wager);
    assertEq(availableBalance(address(atk), address(0)), 0);
  }
}
