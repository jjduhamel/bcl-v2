// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Escrow.t.sol';

contract EscrowERC20DepositTest is EscrowTest {
  function setUp() public {
    deposit(p1, gameId, address(token), wager);
  }

  function testTransfersTokensToContract() public {
    assertEq(token.balanceOf(address(this)), wager);
    assertEq(token.balanceOf(p1), 1000 ether - wager);
  }

  function testUpdatesEscrowBalance() public {
    assertEq(balanceERC20(p1, gameId, address(token)), wager);
  }

  function testRefundMovesToEarnings() public {
    refundERC20(p1, gameId, address(token));
    assertEq(balanceERC20(p1, gameId, address(token)), 0);
    assertEq(earningsERC20(p1, address(token)), wager);
  }

  function testRefundOnZeroIsNoop() public {
    refundERC20(p2, gameId, address(token));
    assertEq(earningsERC20(p2, address(token)), 0);
  }
}

contract EscrowETHDepositTest is EscrowETHTest {
  function setUp() public {
    this.depositETH{value: wager}(p1, gameId, address(0), wager);
  }

  function testUpdatesEscrowBalance() public {
    assertEq(balanceERC20(p1, gameId, address(0)), wager);
  }

  function testInsufficientValueReverts() public {
    vm.expectRevert('InsufficientFunds');
    this.depositETH{value: wager - 1}(p2, gameId, address(0), wager);
  }

  function testRefundMovesToEarnings() public {
    refundERC20(p1, gameId, address(0));
    assertEq(balanceERC20(p1, gameId, address(0)), 0);
    assertEq(earningsERC20(p1, address(0)), wager);
  }

  function testRefundOnZeroIsNoop() public {
    refundERC20(p2, gameId, address(0));
    assertEq(earningsERC20(p2, address(0)), 0);
  }
}
