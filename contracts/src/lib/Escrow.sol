// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/token/ERC20/IERC20.sol';
import '@oz/token/ERC20/utils/SafeERC20.sol';
import '../IChessEngine.sol';

abstract contract Escrow {
  using SafeERC20 for IERC20;

  // player -> gameId -> token -> deposited amount (address(0) token = ETH)
  mapping(address => mapping(uint => mapping(address => uint))) private __escrowERC20;
  // player -> token -> claimable amount (address(0) player = platform fees)
  mapping(address => mapping(address => uint)) private __earningsERC20;

  function balanceERC20(address player, uint gameId, address token) internal view returns (uint) {
    return __escrowERC20[player][gameId][token];
  }

  function refundERC20(address player, uint gameId, address token) internal {
    uint amount = __escrowERC20[player][gameId][token];
    delete __escrowERC20[player][gameId][token];
    __earningsERC20[player][token] += amount;
  }

  function chargeFeeERC20(address player, uint gameId, address token, uint fee) internal {
    __escrowERC20[player][gameId][token] -= fee;
    __earningsERC20[address(0)][token] += fee;
  }

  function disburseERC20(
    address white,
    address black,
    uint gameId,
    address token,
    IChessEngine.GameOutcome outcome
  ) internal {
    uint wBal = __escrowERC20[white][gameId][token];
    uint bBal = __escrowERC20[black][gameId][token];
    delete __escrowERC20[white][gameId][token];
    delete __escrowERC20[black][gameId][token];
    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      __earningsERC20[white][token] += wBal + bBal;
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      __earningsERC20[black][token] += wBal + bBal;
    } else {
      __earningsERC20[white][token] += wBal;
      __earningsERC20[black][token] += bBal;
    }
  }

  function earningsERC20(address player, address token) internal view returns (uint) {
    return __earningsERC20[player][token];
  }

  /*
   * Deposit
   */

  function _depositETH(address player, uint gameId, uint amount) private {
    require(msg.value >= amount, 'InsufficientFunds');
    __escrowERC20[player][gameId][address(0)] += amount;
  }

  function _depositERC20(address player, uint gameId, address token, uint amount) private {
    require(IERC20(token).allowance(player, address(this)) >= amount, 'InsufficientFunds');
    IERC20(token).safeTransferFrom(player, address(this), amount);
    __escrowERC20[player][gameId][token] += amount;
  }

  function deposit(address player, uint gameId, address token, uint amount) internal {
    if (token == address(0)) _depositETH(player, gameId, amount);
    else _depositERC20(player, gameId, token, amount);
  }

  /*
   * Withdraw
   */

  function _withdrawETH(address player) private {
    uint amount = __earningsERC20[player][address(0)];
    require(amount > 0, 'InsufficientBalance');
    __earningsERC20[player][address(0)] = 0;
    payable(player).transfer(amount);
  }

  function _withdrawERC20(address player, address token) private {
    uint amount = __earningsERC20[player][token];
    require(amount > 0, 'InsufficientBalance');
    __earningsERC20[player][token] = 0;
    IERC20(token).safeTransfer(player, amount);
  }

  function withdraw(address player, address token) internal {
    if (token == address(0)) _withdrawETH(player);
    else _withdrawERC20(player, token);
  }

  /*
   * Platform withdraw
   */

  function _withdrawPlatformETH(address payable receiver) private {
    uint amount = __earningsERC20[address(0)][address(0)];
    __earningsERC20[address(0)][address(0)] = 0;
    if (amount > 0) receiver.transfer(amount);
  }

  function _withdrawPlatformERC20(address token, address receiver) private {
    uint amount = __earningsERC20[address(0)][token];
    __earningsERC20[address(0)][token] = 0;
    if (amount > 0) IERC20(token).safeTransfer(receiver, amount);
  }

  function withdrawPlatform(address token, address receiver) internal {
    if (token == address(0)) _withdrawPlatformETH(payable(receiver));
    else _withdrawPlatformERC20(token, receiver);
  }
}
