// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@lib/Escrow.sol';
import '@src/IChessEngine.sol';
import './MockERC20Token.sol';

abstract contract EscrowTest is Test, Escrow {
  MockERC20Token token;
  address p1;
  address p2;
  uint gameId = 1;
  uint wager = 100 ether;
  uint fee = wager / 100;

  constructor() {
    p1 = makeAddr('player1');
    p2 = makeAddr('player2');
    token = new MockERC20Token();
    token.mint(p1, 1000 ether);
    token.mint(p2, 1000 ether);
    vm.prank(p1);
    token.approve(address(this), type(uint256).max);
    vm.prank(p2);
    token.approve(address(this), type(uint256).max);
  }
}

abstract contract EscrowETHTest is EscrowTest {
  // In real-life, deposit would be called by some payable function (i.e. acceptChallenge)
  function depositETH(address player, uint gameId, address token, uint amount)
  public payable {
    require(token == address(0), 'InvalidToken');
    deposit(player, gameId, token, amount);
  }

  constructor() {
    p1 = makeAddr('player1');
    p2 = makeAddr('player2');
    vm.deal(address(this), 1000 ether);
  }
}
