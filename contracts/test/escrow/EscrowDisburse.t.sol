// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@src/lib/GameIDToTokenDepositMap.sol';
import './Escrow.t.sol';
import './MockERC20Token.sol';

contract EscrowERC20DisburseTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager);
    deposit(p2, gameId, address(token), wager);
  }

  function testWhiteWins() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(earnings(p1, address(token)), 2 * wager);
    assertEq(earnings(p2, address(token)), 0);
  }

  function testBlackWins() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(earnings(p1, address(token)), 0);
    assertEq(earnings(p2, address(token)), 2 * wager);
  }

  function testDraw() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(earnings(p1, address(token)), wager);
    assertEq(earnings(p2, address(token)), wager);
  }

  function testDisburseClearsEscrow() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(escrow(p1, gameId).amount, 0);
    assertEq(escrow(p2, gameId).amount, 0);
  }

  function testDisburseSameGameTwiceReverts() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    vm.expectRevert(GameIDToTokenDepositMap.NoDeposit.selector);
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
  }
}

contract EscrowETHDisburseTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    this.depositETH{value: wager}(p2, gameId, address(0), wager);
  }

  function testWhiteWins() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(earnings(p1, address(0)), 2 * wager);
    assertEq(earnings(p2, address(0)), 0);
  }

  function testBlackWins() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(earnings(p1, address(0)), 0);
    assertEq(earnings(p2, address(0)), 2 * wager);
  }

  function testDraw() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(earnings(p1, address(0)), wager);
    assertEq(earnings(p2, address(0)), wager);
  }

  function testDisburseClearsEscrow() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(escrow(p1, gameId).amount, 0);
    assertEq(escrow(p2, gameId).amount, 0);
  }

  function testDisburseSameGameTwiceReverts() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    vm.expectRevert(GameIDToTokenDepositMap.NoDeposit.selector);
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
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
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    deposit(p2, gameId, address(token2), wager);
  }

  function testWhiteWinsGetsBothTokens() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.WhiteWon);
    assertEq(earnings(p1, address(0)), wager);
    assertEq(earnings(p1, address(token2)), wager);
    assertEq(earnings(p2, address(0)), 0);
    assertEq(earnings(p2, address(token2)), 0);
  }

  function testBlackWinsGetsBothTokens() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.BlackWon);
    assertEq(earnings(p2, address(0)), wager);
    assertEq(earnings(p2, address(token2)), wager);
    assertEq(earnings(p1, address(0)), 0);
    assertEq(earnings(p1, address(token2)), 0);
  }

  function testDrawEachKeepsOwnToken() public {
    disburse(p1, p2, gameId, IChessEngine.GameOutcome.Draw);
    assertEq(earnings(p1, address(0)), wager);
    assertEq(earnings(p1, address(token2)), 0);
    assertEq(earnings(p2, address(token2)), wager);
    assertEq(earnings(p2, address(0)), 0);
  }
}
