// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';
import './MockERC20Token.sol';

contract EscrowERC20DisburseTest is EscrowTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(token));
    _stake(p2, gameId, wager, address(token));
  }

  function testWhiteWins() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(uint(unlockedBalance(p1, address(token))), 2 * wager);
    assertEq(uint(unlockedBalance(p2, address(token))), 0);
  }

  function testBlackWins() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(uint(unlockedBalance(p1, address(token))), 0);
    assertEq(uint(unlockedBalance(p2, address(token))), 2 * wager);
  }

  function testDraw() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(uint(unlockedBalance(p1, address(token))), wager);
    assertEq(uint(unlockedBalance(p2, address(token))), wager);
  }

  function testDisburseClearsEscrow() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(currentDeposit(p2, gameId).amount, 0);
  }
}

contract EscrowETHDisburseTest is EscrowETHTest {
  function setUp() public {
    _stake(p1, gameId, wager, address(0));
    _stake(p2, gameId, wager, address(0));
  }

  function testWhiteWins() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(uint(unlockedBalance(p1, address(0))), 2 * wager);
    assertEq(uint(unlockedBalance(p2, address(0))), 0);
  }

  function testBlackWins() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(uint(unlockedBalance(p1, address(0))), 0);
    assertEq(uint(unlockedBalance(p2, address(0))), 2 * wager);
  }

  function testDraw() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(uint(unlockedBalance(p1, address(0))), wager);
    assertEq(uint(unlockedBalance(p2, address(0))), wager);
  }

  function testDisburseClearsEscrow() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(currentDeposit(p1, gameId).amount, 0);
    assertEq(currentDeposit(p2, gameId).amount, 0);
  }

  // A loser carrying gas debt must not block disbursal: their stake settles the debt to the
  // platform first, and only the remainder is awarded to the winner. (Exercises unsafeCredit.)
  function testDisburseLoserInGasDebtSettlesFromStake() public {
    _chargeGas(p2, 30 ether, 0);  // loser p2 had 0 unlocked, so this is pure debt
    assertEq(unlockedBalance(p2, address(0)), -int(30 ether));
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);   // must not revert
    assertEq(uint(unlockedBalance(p1, address(0))), 2 * wager - 30 ether);  // own + loser's net stake
    assertEq(unlockedBalance(p2, address(0)), 0);                           // debt cleared
    assertEq(uint(availableBalance(address(0), address(0))), 30 ether);     // platform recovered it
  }

  // A winner carrying gas debt settles it from their own returned stake.
  function testDisburseWinnerInGasDebtSettlesFromOwnStake() public {
    _chargeGas(p1, 30 ether, 0);
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(uint(unlockedBalance(p1, address(0))), 2 * wager - 30 ether);
    assertEq(unlockedBalance(p2, address(0)), 0);
    assertEq(uint(availableBalance(address(0), address(0))), 30 ether);
  }
}

contract EscrowMixedTokenDisburseTest is EscrowETHTest {
  MockERC20Token token2;

  constructor() {
    token2 = new MockERC20Token();
    token2.mint(p2, 1000 ether);
    vm.prank(p2);
    token2.approve(address(this), type(uint256).max);
  }

  function setUp() public {
    _stake(p1, gameId, wager, address(0));
    _stake(p2, gameId, wager, address(token2));
  }

  function testWhiteWinsGetsBothTokens() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(uint(unlockedBalance(p1, address(0))), wager);
    assertEq(uint(unlockedBalance(p1, address(token2))), wager);
    assertEq(uint(unlockedBalance(p2, address(0))), 0);
    assertEq(uint(unlockedBalance(p2, address(token2))), 0);
  }

  function testBlackWinsGetsBothTokens() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(uint(unlockedBalance(p2, address(0))), wager);
    assertEq(uint(unlockedBalance(p2, address(token2))), wager);
    assertEq(uint(unlockedBalance(p1, address(0))), 0);
    assertEq(uint(unlockedBalance(p1, address(token2))), 0);
  }

  function testDrawEachKeepsOwnToken() public {
    _disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(uint(unlockedBalance(p1, address(0))), wager);
    assertEq(uint(unlockedBalance(p1, address(token2))), 0);
    assertEq(uint(unlockedBalance(p2, address(token2))), wager);
    assertEq(uint(unlockedBalance(p2, address(0))), 0);
  }
}
