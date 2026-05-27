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

// Escrow accounting + custody as an external (linked) library: its heavy EnumerableMap machinery
// is deployed once and delegatecall-linked out of the calling contract's bytecode. Every function
// runs in the caller's context (delegatecall preserves address(this) and msg.value), so funds and
// state live on the caller — EscrowContract below holds the single `EscrowData` and exposes thin wrappers.
library Escrow {
  using SafeERC20 for IERC20;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using TokenDepositMap for TokenDepositMap.GameIDTokenDepositMap;

  error EscrowLocked();
  error AmountOverflow();
  error InvalidToken();
  error InvalidDeposit();
  error InsufficientBalance();
  error TransferFailed();

  struct EscrowData {
    // player -> gameId -> token deposit (address(0) token = ETH)
    mapping(address => TokenDepositMap.GameIDTokenDepositMap) restricted;
    // player -> token -> claimable amount (address(0) player = platform fees)
    mapping(address => EnumerableMap.AddressToUintMap) released;
    // Platform fee percentage (0-100) applied to each player's wager at game start
    uint feePerc;
    // Reserved slots for future Escrow state. Decrement when appending a field so the
    // storage of anything declared after `__escrow` in the caller stays put across upgrades.
    uint256[47] __gap;
  }

  function currentDeposit(EscrowData storage escrow, address player, uint gameId) public view returns (TokenDeposit memory) {
    (bool exists, TokenDeposit memory d) = escrow.restricted[player].tryGet(gameId);
    return exists ? d : TokenDeposit(address(0), 0);
  }

  function tokens(EscrowData storage escrow, address player) public view returns (address[] memory) {
    return escrow.released[player].keys();
  }

  function releasedFunds(EscrowData storage escrow, address player, address token) public view returns (uint) {
    (bool exists, uint out) = escrow.released[player].tryGet(token);
    return exists ? out : 0;
  }

  function refund(EscrowData storage escrow, address player, uint gameId) public {
    (bool exists, TokenDeposit memory d) = escrow.restricted[player].tryGet(gameId);
    if (!exists) return;
    escrow.released[player].set(d.token, releasedFunds(escrow, player, d.token) + d.amount);
    escrow.restricted[player].remove(gameId);
  }

  function refund(EscrowData storage escrow, address player, uint gameId, uint amount) public {
    (bool exists, TokenDeposit memory d) = escrow.restricted[player].tryGet(gameId);
    if (!exists || amount == 0) return;
    if (d.amount < amount) revert InsufficientBalance();
    escrow.released[player].set(d.token, releasedFunds(escrow, player, d.token) + amount);
    escrow.restricted[player].set(gameId, d.token, d.amount - amount);
  }

  // Refund any deposit amount above `expected` to the player's released funds.
  // Used at game start to clean up over-deposits accumulated through challenge modifications.
  function refundExcess(EscrowData storage escrow, address player, uint gameId, uint expected) public {
    uint bal = currentDeposit(escrow, player, gameId).amount;
    if (bal > expected) refund(escrow, player, gameId, bal - expected);
  }

  function disburse(
    EscrowData storage escrow,
    address white,
    address black,
    uint gameId,
    IChessEngine.GameOutcome outcome
  ) public {
    TokenDeposit memory wBal = escrow.restricted[white].get(gameId);
    TokenDeposit memory bBal = escrow.restricted[black].get(gameId);
    escrow.restricted[white].remove(gameId);
    escrow.restricted[black].remove(gameId);
    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      escrow.released[white].set(wBal.token, releasedFunds(escrow, white, wBal.token) + wBal.amount);
      escrow.released[white].set(bBal.token, releasedFunds(escrow, white, bBal.token) + bBal.amount);
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      escrow.released[black].set(wBal.token, releasedFunds(escrow, black, wBal.token) + wBal.amount);
      escrow.released[black].set(bBal.token, releasedFunds(escrow, black, bBal.token) + bBal.amount);
    } else if (outcome == IChessEngine.GameOutcome.Draw) {
      escrow.released[white].set(wBal.token, releasedFunds(escrow, white, wBal.token) + wBal.amount);
      escrow.released[black].set(bBal.token, releasedFunds(escrow, black, bBal.token) + bBal.amount);
    } else {
      revert EscrowLocked();
    }
  }

  /*
   * Platform Fee
   */

  function platformFeePerc(EscrowData storage escrow) public view returns (uint) {
    return escrow.feePerc;
  }

  function setPlatformFee(EscrowData storage escrow, uint perc) public {
    escrow.feePerc = perc;
  }

  function platformFee(EscrowData storage escrow, uint wager) public view returns (uint96) {
    return uint96(wager * escrow.feePerc / 100);
  }

  function chargeFee(EscrowData storage escrow, address player, uint gameId, address token) public {
    TokenDeposit memory d = currentDeposit(escrow, player, gameId);
    if (d.amount == 0) return;
    uint96 fee = platformFee(escrow, d.amount);
    // Debit fee from player escrow account
    escrow.restricted[player].set(gameId, d.token, d.amount-fee);
    // Credit fee to platform account (address(0))
    escrow.released[address(0)].set(token, releasedFunds(escrow, address(0), token) + fee);
  }

  /*
   * Deposit
   */

  function _depositETH(EscrowData storage escrow, address player, uint gameId, address token, uint amount) private {
    if (token != address(0)) revert InvalidToken();
    if (msg.value != amount) revert InvalidDeposit();
    TokenDeposit memory d = currentDeposit(escrow, player, gameId);
    if (d.token != address(0)) revert InvalidToken();
    uint total = d.amount + amount;
    if (total > type(uint96).max) revert AmountOverflow();
    escrow.restricted[player].set(gameId, address(0), total);
  }

  function _depositERC20(EscrowData storage escrow, address player, uint gameId, address token, uint amount) private {
    if (token == address(0)) revert InvalidToken();
    TokenDeposit memory d = currentDeposit(escrow, player, gameId);
    // d.amount > 0 distinguishes an existing deposit from "no entry yet".
    // Any prior deposit must match the requested token, even if the prior was ETH (d.token == 0).
    if (d.amount > 0 && d.token != token) revert InvalidToken();
    uint total = d.amount + amount;
    if (total > type(uint96).max) revert AmountOverflow();
    IERC20(token).safeTransferFrom(player, address(this), amount);
    escrow.restricted[player].set(gameId, token, total);
  }

  function deposit(EscrowData storage escrow, address player, uint gameId, address token, uint amount) public {
    ((token == address(0)) ? _depositETH : _depositERC20)(escrow, player, gameId, token, amount);
  }

  /*
   * Release
   */

  function _releaseETH(EscrowData storage escrow, address player, address token) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = releasedFunds(escrow, player, address(0));
    if (amount == 0) revert InsufficientBalance();
    escrow.released[player].set(address(0), 0);
    // .call forwards all gas; .transfer caps at 2300 and fails for smart contract wallets
    (bool ok,) = payable(player).call{value: amount}("");
    if (!ok) revert TransferFailed();
  }

  function _releaseERC20(EscrowData storage escrow, address player, address token) private {
    uint amount = releasedFunds(escrow, player, token);
    if (amount == 0) revert InsufficientBalance();
    escrow.released[player].set(token, 0);
    IERC20(token).safeTransfer(player, amount);
  }

  function release(EscrowData storage escrow, address player, address token) public {
    (token == address(0) ? _releaseETH : _releaseERC20)(escrow, player, token);
  }

  /*
   * Platform release
   */

  function _releasePlatformETH(EscrowData storage escrow, address token, address receiver) private {
    if (token != address(0)) revert InvalidToken();
    uint amount = releasedFunds(escrow, address(0), address(0));
    escrow.released[address(0)].set(address(0), 0);
    if (amount > 0) {
      // .call forwards all gas; .transfer caps at 2300 and fails for smart contract wallets
      (bool ok,) = payable(receiver).call{value: amount}("");
      if (!ok) revert TransferFailed();
    }
  }

  function _releasePlatformERC20(EscrowData storage escrow, address token, address receiver) private {
    uint amount = releasedFunds(escrow, address(0), token);
    escrow.released[address(0)].set(token, 0);
    if (amount > 0) IERC20(token).safeTransfer(receiver, amount);
  }

  function releasePlatformFunds(EscrowData storage escrow, address token, address receiver) public {
    (token == address(0) ? _releasePlatformETH : _releasePlatformERC20)(escrow, token, receiver);
  }
}

// Thin storage holder over the Escrow library. Inherited by the Lobby (and the escrow unit tests):
// keeps the single `EscrowWrapper` plus internal wrappers with the original signatures, so call sites are
// unchanged while the heavy logic is linked out into the Escrow library.
abstract contract EscrowWrapper {
  using Escrow for Escrow.EscrowData;

  Escrow.EscrowData internal __escrow;

  function currentDeposit(address player, uint gameId) internal view returns (TokenDeposit memory) {
    return __escrow.currentDeposit(player, gameId);
  }

  function tokens(address player) internal view returns (address[] memory) {
    return __escrow.tokens(player);
  }

  function releasedFunds(address player, address token) internal view returns (uint) {
    return __escrow.releasedFunds(player, token);
  }

  function refund(address player, uint gameId) internal {
    __escrow.refund(player, gameId);
  }

  function refund(address player, uint gameId, uint amount) internal {
    __escrow.refund(player, gameId, amount);
  }

  function refundExcess(address player, uint gameId, uint expected) internal {
    __escrow.refundExcess(player, gameId, expected);
  }

  function disburse(address white, address black, uint gameId, IChessEngine.GameOutcome outcome) internal {
    __escrow.disburse(white, black, gameId, outcome);
  }

  function chargeFee(address player, uint gameId, address token) internal {
    __escrow.chargeFee(player, gameId, token);
  }

  function deposit(address player, uint gameId, address token, uint amount) internal {
    __escrow.deposit(player, gameId, token, amount);
  }

  function release(address player, address token) internal {
    __escrow.release(player, token);
  }

  function releasePlatformFunds(address token, address receiver) internal {
    __escrow.releasePlatformFunds(token, receiver);
  }

  function platformFeePerc() public view returns (uint) {
    return __escrow.platformFeePerc();
  }

  function _setPlatformFee(uint perc) internal {
    __escrow.setPlatformFee(perc);
  }

  function _platformFee(uint wager) internal view returns (uint96) {
    return __escrow.platformFee(wager);
  }
}
