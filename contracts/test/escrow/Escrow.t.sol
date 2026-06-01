// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@lib/Escrow.sol';
import '@src/IChessEngine.sol';
import './MockERC20Token.sol';

abstract contract EscrowTest is EscrowWrapper, Test {
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
    _setPlatformFee(1);
  }

  // External wrappers — vm.expectRevert in modern forge matches the next external call frame,
  // and the wrapper functions kick off with a delegatecall to the linked library. Tests using
  // expectRevert call these instead so the whole wrapper body is one external call.
  function ext_deposit(address player, uint amount, address tok) external payable {
    deposit(player, amount, tok);
  }
  function ext_withdraw(address player, address tok) external {
    withdraw(player, tok);
  }
}

abstract contract EscrowETHTest is EscrowTest {
  using Escrow for Escrow.EscrowAccount;

  // In real-life, deposit would be called by some payable function (i.e. acceptChallenge)
  function depositETH(address player, uint gameId, address token, uint amount)
  public payable {
    require(token == address(0), 'InvalidToken');
    deposit(player, amount, token);
    lock(player, gameId, amount, token);
  }

  constructor() {
    p1 = makeAddr('player1');
    p2 = makeAddr('player2');
    vm.deal(address(this), 1000 ether);
  }
}
