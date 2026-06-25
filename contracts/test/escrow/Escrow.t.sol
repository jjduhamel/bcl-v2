// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@lib/EscrowLib.sol';
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
    _deposit(player, amount, tok);
  }
  function ext_withdraw(address player, address tok) external {
    _withdraw(player, tok);
  }
  function ext_escrow(address player, uint id, uint amount, address tok) external payable {
    _escrow(player, id, amount, tok);
  }

  // Seed `player`'s withdrawable balance, depositing AS the player so _deposit's
  // `account == msg.sender` guard holds. Inline-ETH banking now lives at the Lobby layer
  // (_handleETHDeposit), so escrow-level tests fund available balance directly here.
  function _fund(address player, uint amount, address tok) internal {
    if (tok == address(0)) {
      // Pranked sender pays the call's value, so give the player the ETH to deposit.
      vm.deal(player, player.balance + amount);
      vm.prank(player);
      this.ext_deposit{ value: amount }(player, amount, tok);
    } else {
      vm.prank(player);
      this.ext_deposit(player, amount, tok);
    }
  }

  // Seed + lock into a game's escrow — the common "player has staked a wager" setup.
  function _stake(address player, uint id, uint amount, address tok) internal {
    _fund(player, amount, tok);
    _lock(player, id, amount, tok);
  }

  // Mirrors Lobby.finishGame's escrow flow: refund both stakes, award the loser's net stake.
  function _disburse(address white, address black, uint id, IChessEngine.GameOutcome outcome) internal {
    TokenDeposit memory wPrize = _refund(white, id);
    TokenDeposit memory bPrize = _refund(black, id);
    if (outcome == IChessEngine.GameOutcome.WhiteWon) _award(white, black, bPrize);
    else if (outcome == IChessEngine.GameOutcome.BlackWon) _award(black, white, wPrize);
  }
}

abstract contract EscrowETHTest is EscrowTest {
  using EscrowLib for EscrowLib.EscrowAccount;

  constructor() {
    vm.deal(address(this), 1000 ether);
  }
}
