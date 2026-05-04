// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/token/ERC20/IERC20.sol';
import '@oz/token/ERC20/utils/SafeERC20.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '../IChessEngine.sol';
import './GameIDToTokenDepositMap.sol';

abstract contract Escrow {
  using SafeERC20 for IERC20;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using GameIDToTokenDepositMap for GameIDToTokenDepositMap.Map;

  error InvalidToken();
  error InsufficientFunds();
  error AmountOverflow();
  error InsufficientBalance();
  error TransferFailed();

  // player -> gameId -> token deposit (address(0) token = ETH)
  mapping(address => GameIDToTokenDepositMap.Map) private __escrow;
  // player -> token -> claimable amount (address(0) player = platform fees)
  mapping(address => EnumerableMap.AddressToUintMap) private __earnings;

  function escrow(address player, uint gameId) internal view returns (TokenDeposit memory) {
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    return exists ? d : TokenDeposit(address(0), 0);
  }

  function tokens(address player) internal view returns (address[] memory) {
    return __earnings[player].keys();
  }

  function earnings(address player, address token) internal view returns (uint) {
    (bool exists, uint out) = __earnings[player].tryGet(token);
    return exists ? out : 0;
  }

  function refund(address player, uint gameId) internal {
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    if (!exists) return;
    __earnings[player].set(d.token, earnings(player, d.token) + d.amount);
    __escrow[player].remove(gameId);
  }

  function refund(address player, uint gameId, uint amount) internal {
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    if (!exists || amount == 0) return;
    if (d.amount < amount) revert InsufficientFunds();
    __earnings[player].set(d.token, earnings(player, d.token) + amount);
    __escrow[player].set(gameId, d.token, d.amount - amount);
  }

  function disburse(
    address white,
    address black,
    uint gameId,
    IChessEngine.GameOutcome outcome
  ) internal {
    TokenDeposit memory wBal = __escrow[white].get(gameId);
    TokenDeposit memory bBal = __escrow[black].get(gameId);
    __escrow[white].remove(gameId);
    __escrow[black].remove(gameId);
    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      __earnings[white].set(wBal.token, earnings(white, wBal.token) + wBal.amount);
      __earnings[white].set(bBal.token, earnings(white, bBal.token) + bBal.amount);
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      __earnings[black].set(wBal.token, earnings(black, wBal.token) + wBal.amount);
      __earnings[black].set(bBal.token, earnings(black, bBal.token) + bBal.amount);
    } else {
      __earnings[white].set(wBal.token, earnings(white, wBal.token) + wBal.amount);
      __earnings[black].set(bBal.token, earnings(black, bBal.token) + bBal.amount);
    }
  }

  function chargeFee(address player, uint gameId, address token, uint fee) internal {
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    if (!exists) return;  // Don't charge any fee for zero-wager games
    if (d.token != token) revert InvalidToken();
    if (d.amount < fee) revert InsufficientFunds();
    d.amount -= uint96(fee);
    __escrow[player].set(gameId, d.token, d.amount);
    __earnings[address(0)].set(token, earnings(address(0), token) + fee);
  }

  /*
   * Deposit
   */

  function _depositETH(address player, uint gameId, address token, uint amount) private {
    if (msg.value < amount) revert InsufficientFunds();
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    if (exists && d.token != address(0)) revert InvalidToken();
    uint total = exists ? d.amount + amount : amount;
    __escrow[player].set(gameId, address(0), total);
  }

  function _depositERC20(address player, uint gameId, address token, uint amount) private {
    (bool exists, TokenDeposit memory d) = __escrow[player].tryGet(gameId);
    if (exists && d.token != token) revert InvalidToken();
    uint total = exists ? d.amount + amount : amount;
    if (total > type(uint96).max) revert AmountOverflow();
    IERC20(token).safeTransferFrom(player, address(this), amount);
    __escrow[player].set(gameId, token, total);
  }

  function deposit(address player, uint gameId, address token, uint amount) internal {
    ((token == address(0)) ? _depositETH : _depositERC20)(player, gameId, token, amount);
  }

  /*
   * Withdraw
   */

  function _withdrawETH(address player, address token) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = earnings(player, address(0));
    if (amount == 0) revert InsufficientBalance();
    __earnings[player].set(address(0), 0);
    // Apparently this is more gas efficient than payable(receiver).transfer(amount);
    (bool ok,) = payable(player).call{value: amount}("");
    if (!ok) revert TransferFailed();
  }

  function _withdrawERC20(address player, address token) private {
    uint amount = earnings(player, token);
    if (amount == 0) revert InsufficientBalance();
    __earnings[player].set(token, 0);
    IERC20(token).safeTransfer(player, amount);
  }

  function withdraw(address player, address token) internal {
    (token == address(0) ? _withdrawETH : _withdrawERC20)(player, token);
  }

  /*
   * Platform withdraw
   */

  function _withdrawPlatformETH(address token, address receiver) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = earnings(address(0), address(0));
    __earnings[address(0)].set(address(0), 0);
    if (amount > 0) {
      // Apparently this is more gas efficient than payable(receiver).transfer(amount);
      (bool ok,) = payable(receiver).call{value: amount}("");
      if (!ok) revert TransferFailed();
    }
  }

  function _withdrawPlatformERC20(address token, address receiver) private {
    uint amount = earnings(address(0), token);
    __earnings[address(0)].set(token, 0);
    if (amount > 0) IERC20(token).safeTransfer(receiver, amount);
  }

  function withdrawPlatformFunds(address token, address receiver) internal {
    (token == address(0) ? _withdrawPlatformETH : _withdrawPlatformERC20)(token, payable(receiver));
  }
}
