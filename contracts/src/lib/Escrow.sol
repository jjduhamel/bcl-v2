// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/token/ERC20/IERC20.sol';
import '@oz/token/ERC20/utils/SafeERC20.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '../IChessEngine.sol';

// token (160 bits) | amount (96 bits) packed into bytes32
struct TokenDeposit {
  address token;
  uint96 amount;
}

abstract contract EscrowContract {
  using SafeERC20 for IERC20;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using TokenDepositMap for TokenDepositMap.GameIDTokenDepositMap;

  error EscrowLocked();
  error AmountOverflow();
  error InvalidToken();
  error InvalidDeposit();
  error InsufficientBalance();
  error TransferFailed();

  // player -> gameId -> token deposit (address(0) token = ETH)
  mapping(address => TokenDepositMap.GameIDTokenDepositMap) private __restricted;
  // player -> token -> claimable amount (address(0) player = platform fees)
  mapping(address => EnumerableMap.AddressToUintMap) private __released;
  // Platform fee percentage (0-100) applied to each player's wager at game start
  uint private __platformFeePerc;

  // Reserved slots for future Escrow state additions. Adding a new state variable
  // above the gap means decrementing the gap size by the same amount, preserving
  // the storage layout of any inheriting contract across upgrades.
  uint256[47] private __gap;

  function currentDeposit(address player, uint gameId) internal view returns (TokenDeposit memory) {
    (bool exists, TokenDeposit memory d) = __restricted[player].tryGet(gameId);
    return exists ? d : TokenDeposit(address(0), 0);
  }

  // TODO: Remove this
  function restrictedFunds(address player, uint gameId) internal view returns (TokenDeposit memory) {
    return currentDeposit(player, gameId);
  }

  function tokens(address player) internal view returns (address[] memory) {
    return __released[player].keys();
  }

  function releasedFunds(address player, address token) internal view returns (uint) {
    (bool exists, uint out) = __released[player].tryGet(token);
    return exists ? out : 0;
  }

  function refund(address player, uint gameId) internal {
    (bool exists, TokenDeposit memory d) = __restricted[player].tryGet(gameId);
    if (!exists) return;
    __released[player].set(d.token, releasedFunds(player, d.token) + d.amount);
    __restricted[player].remove(gameId);
  }

  function refund(address player, uint gameId, uint amount) internal {
    (bool exists, TokenDeposit memory d) = __restricted[player].tryGet(gameId);
    if (!exists || amount == 0) return;
    if (d.amount < amount) revert InsufficientBalance();
    __released[player].set(d.token, releasedFunds(player, d.token) + amount);
    __restricted[player].set(gameId, d.token, d.amount - amount);
  }

  // Refund any deposit amount above `expected` to the player's released funds.
  // Used at game start to clean up over-deposits accumulated through challenge modifications.
  function refundExcess(address player, uint gameId, uint expected) internal {
    uint bal = currentDeposit(player, gameId).amount;
    if (bal > expected) refund(player, gameId, bal - expected);
  }

  function disburse(
    address white,
    address black,
    uint gameId,
    IChessEngine.GameOutcome outcome
  ) internal {
    TokenDeposit memory wBal = __restricted[white].get(gameId);
    TokenDeposit memory bBal = __restricted[black].get(gameId);
    __restricted[white].remove(gameId);
    __restricted[black].remove(gameId);
    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      __released[white].set(wBal.token, releasedFunds(white, wBal.token) + wBal.amount);
      __released[white].set(bBal.token, releasedFunds(white, bBal.token) + bBal.amount);
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      __released[black].set(wBal.token, releasedFunds(black, wBal.token) + wBal.amount);
      __released[black].set(bBal.token, releasedFunds(black, bBal.token) + bBal.amount);
    } else if (outcome == IChessEngine.GameOutcome.Draw) {
      __released[white].set(wBal.token, releasedFunds(white, wBal.token) + wBal.amount);
      __released[black].set(bBal.token, releasedFunds(black, bBal.token) + bBal.amount);
    } else {
      revert EscrowLocked();
    }
  }

  /*
   * Platform Fee
   */

  function platformFeePerc() public view returns (uint) {
    return __platformFeePerc;
  }

  function _setPlatformFee(uint perc) internal {
    __platformFeePerc = perc;
  }

  function _platformFee(uint wager) internal view returns (uint96) {
    return uint96(wager * __platformFeePerc / 100);
  }

  function chargeFee(address player, uint gameId, address token) internal {
    TokenDeposit memory d = currentDeposit(player, gameId);
    if (d.amount == 0) return;
    uint96 fee = _platformFee(d.amount);
    // Debit fee from player escrow account
    __restricted[player].set(gameId, d.token, d.amount-fee);
    // Credit fee to platform account (address(0))
    __released[address(0)].set(token, releasedFunds(address(0), token) + fee);
  }

  /*
   * Deposit
   */

  function _depositETH(address player, uint gameId, address token, uint amount) private {
    if (token != address(0)) revert InvalidToken();
    if (msg.value != amount) revert InvalidDeposit();
    TokenDeposit memory d = currentDeposit(player, gameId);
    if (d.token != address(0)) revert InvalidToken();
    uint total = d.amount + amount;
    if (total > type(uint96).max) revert AmountOverflow();
    __restricted[player].set(gameId, address(0), total);
  }

  function _depositERC20(address player, uint gameId, address token, uint amount) private {
    if (token == address(0)) revert InvalidToken();
    TokenDeposit memory d = currentDeposit(player, gameId);
    // d.amount > 0 distinguishes an existing deposit from "no entry yet".
    // Any prior deposit must match the requested token, even if the prior was ETH (d.token == 0).
    if (d.amount > 0 && d.token != token) revert InvalidToken();
    uint total = d.amount + amount;
    if (total > type(uint96).max) revert AmountOverflow();
    IERC20(token).safeTransferFrom(player, address(this), amount);
    __restricted[player].set(gameId, token, total);
  }

  function deposit(address player, uint gameId, address token, uint amount) internal {
    ((token == address(0)) ? _depositETH : _depositERC20)(player, gameId, token, amount);
  }

  /*
   * Release
   */

  function _releaseETH(address player, address token) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = releasedFunds(player, address(0));
    if (amount == 0) revert InsufficientBalance();
    __released[player].set(address(0), 0);
    // .call forwards all gas; .transfer caps at 2300 and fails for smart contract wallets
    (bool ok,) = payable(player).call{value: amount}("");
    if (!ok) revert TransferFailed();
  }

  function _releaseERC20(address player, address token) private {
    uint amount = releasedFunds(player, token);
    if (amount == 0) revert InsufficientBalance();
    __released[player].set(token, 0);
    IERC20(token).safeTransfer(player, amount);
  }

  function release(address player, address token) internal {
    (token == address(0) ? _releaseETH : _releaseERC20)(player, token);
  }

  /*
   * Platform release
   */

  function _releasePlatformETH(address token, address receiver) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = releasedFunds(address(0), address(0));
    __released[address(0)].set(address(0), 0);
    if (amount > 0) {
      // .call forwards all gas; .transfer caps at 2300 and fails for smart contract wallets
      (bool ok,) = payable(receiver).call{value: amount}("");
      if (!ok) revert TransferFailed();
    }
  }

  function _releasePlatformERC20(address token, address receiver) private {
    uint amount = releasedFunds(address(0), token);
    __released[address(0)].set(token, 0);
    if (amount > 0) IERC20(token).safeTransfer(receiver, amount);
  }

  function releasePlatformFunds(address token, address receiver) internal {
    (token == address(0) ? _releasePlatformETH : _releasePlatformERC20)(token, payable(receiver));
  }
}

library TokenDepositMap {
  using EnumerableMap for EnumerableMap.UintToBytes32Map;

  struct GameIDTokenDepositMap {
    EnumerableMap.UintToBytes32Map _inner;
  }

  error NoDeposit();
  error AmountOverflow();

  function _encode(address token, uint96 amount) private pure returns (bytes32) {
    return bytes32((uint256(uint160(token)) << 96) | uint256(amount));
  }

  function _decode(bytes32 val) private pure returns (TokenDeposit memory) {
    return TokenDeposit(
      address(uint160(uint256(val) >> 96)),
      uint96(uint256(val))
    );
  }

  function set(GameIDTokenDepositMap storage map, uint gameId, address token, uint amount) internal {
    if (amount > type(uint96).max) revert AmountOverflow();
    map._inner.set(gameId, _encode(token, uint96(amount)));
  }

  function get(GameIDTokenDepositMap storage map, uint gameId) internal view returns (TokenDeposit memory) {
    (bool exists, bytes32 val) = map._inner.tryGet(gameId);
    if (!exists) revert NoDeposit();
    return _decode(val);
  }

  function tryGet(GameIDTokenDepositMap storage map, uint gameId) internal view returns (bool, TokenDeposit memory) {
    (bool exists, bytes32 val) = map._inner.tryGet(gameId);
    return (exists, exists ? _decode(val) : TokenDeposit(address(0), 0));
  }

  function remove(GameIDTokenDepositMap storage map, uint gameId) internal returns (bool) {
    return map._inner.remove(gameId);
  }

  function length(GameIDTokenDepositMap storage map) internal view returns (uint) {
    return map._inner.length();
  }

  function at(GameIDTokenDepositMap storage map, uint index) internal view returns (uint, TokenDeposit memory) {
    (uint gameId, bytes32 val) = map._inner.at(index);
    return (gameId, _decode(val));
  }
}
