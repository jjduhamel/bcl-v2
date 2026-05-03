// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20DisburseTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager);
    deposit(p2, gameId, address(token), wager);
  }

  function testWhiteWins() public {
    disburseERC20(p1, p2, gameId, address(token), IChessEngine.GameOutcome.WhiteWon);
    assertEq(earningsERC20(p1, address(token)), 2 * wager);
    assertEq(earningsERC20(p2, address(token)), 0);
  }

  function testBlackWins() public {
    disburseERC20(p1, p2, gameId, address(token), IChessEngine.GameOutcome.BlackWon);
    assertEq(earningsERC20(p1, address(token)), 0);
    assertEq(earningsERC20(p2, address(token)), 2 * wager);
  }

  function testDraw() public {
    disburseERC20(p1, p2, gameId, address(token), IChessEngine.GameOutcome.Draw);
    assertEq(earningsERC20(p1, address(token)), wager);
    assertEq(earningsERC20(p2, address(token)), wager);
  }

  function testDisburseClearsEscrow() public {
    disburseERC20(p1, p2, gameId, address(token), IChessEngine.GameOutcome.WhiteWon);
    assertEq(balanceERC20(p1, gameId, address(token)), 0);
    assertEq(balanceERC20(p2, gameId, address(token)), 0);
  }
}

contract EscrowETHDisburseTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
    this.depositETH{value: wager}(p2, gameId, address(0), wager);
  }

  function testWhiteWins() public {
    disburseERC20(p1, p2, gameId, address(0), IChessEngine.GameOutcome.WhiteWon);
    assertEq(earningsERC20(p1, address(0)), 2 * wager);
    assertEq(earningsERC20(p2, address(0)), 0);
  }

  function testBlackWins() public {
    disburseERC20(p1, p2, gameId, address(0), IChessEngine.GameOutcome.BlackWon);
    assertEq(earningsERC20(p1, address(0)), 0);
    assertEq(earningsERC20(p2, address(0)), 2 * wager);
  }

  function testDraw() public {
    disburseERC20(p1, p2, gameId, address(0), IChessEngine.GameOutcome.Draw);
    assertEq(earningsERC20(p1, address(0)), wager);
    assertEq(earningsERC20(p2, address(0)), wager);
  }

  function testDisburseClearsEscrow() public {
    disburseERC20(p1, p2, gameId, address(0), IChessEngine.GameOutcome.WhiteWon);
    assertEq(balanceERC20(p1, gameId, address(0)), 0);
    assertEq(balanceERC20(p2, gameId, address(0)), 0);
  }
}
