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

// Escrow accounting + custody as an external (linked) library: heavy EnumerableMap machinery is
// deployed once and delegatecall-linked out of the calling contract's bytecode. Every function runs
// in the caller's context (delegatecall preserves address(this) and msg.value), so funds and state
// live on the caller — `EscrowWrapper` below holds the per-player `EscrowAccount` mapping and
// exposes thin wrappers. Library is transfer-free: ERC20 transferFrom is performed by the wrapper.
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

  struct EscrowAccount {
    // gameId -> per-game locked deposit
    TokenDepositMap.GameIDTokenDepositMap __accounts;
    // token -> total locked across games (TODO Phase 1 #8: drop — duplicates Σ __accounts)
    EnumerableMap.AddressToUintMap __restricted;
    // token -> withdrawable balance
    EnumerableMap.AddressToUintMap __available;
  }

  function account(EscrowAccount storage escrow, uint gameId) public view returns (TokenDeposit memory) {
    (bool exists, TokenDeposit memory d) = escrow.__accounts.tryGet(gameId);
    return exists ? d : TokenDeposit(address(0), 0);
  }

  // TODO: Should merge with escrow.__restricted.keys()
  function tokens(EscrowAccount storage escrow) public view returns (address[] memory) {
    return escrow.__available.keys();
  }

  function available(EscrowAccount storage escrow, address token) public view returns (uint) {
    (bool exists, uint out) = escrow.__available.tryGet(token);
    return exists ? out : 0;
  }

  function restricted(EscrowAccount storage escrow, address token) public view returns (uint) {
    (bool exists, uint out) = escrow.__restricted.tryGet(token);
    return exists ? out : 0;
  }

  /*
   * Debit / credit - Increase or decrease available balance.  Needed to moving funds
   * between accounts.
   */

  // Debit increases this account's available balance.
  function debit(EscrowAccount storage escrow, uint amount, address token) public {
    uint avail = available(escrow, token);
    escrow.__available.set(token, avail + amount);
  }

  // Credit reduces this account's available balance.
  function credit(EscrowAccount storage escrow, uint amount, address token) public {
    uint avail = available(escrow, token);
    if (amount > avail) revert InsufficientBalance();
    escrow.__available.set(token, avail - amount);
  }

  /*
   * Lock / release — move between __available and __accounts (per-game restricted).
   */

  function lock(EscrowAccount storage escrow, uint gameId, uint amount, address token) internal {
    TokenDeposit memory d = account(escrow, gameId);
    uint avail = available(escrow, token);
    uint locked = restricted(escrow, token);
    if (avail < amount) revert InsufficientBalance();
    if (d.amount > 0 && d.token != token) revert InvalidToken();
    uint total = d.amount + amount;
    if (total > type(uint96).max) revert AmountOverflow();
    escrow.__accounts.set(gameId, token, total);
    escrow.__available.set(token, avail - amount);
    escrow.__restricted.set(token, locked + amount);
  }

  function release(EscrowAccount storage escrow, uint gameId, uint amount) public {
    TokenDeposit memory d = account(escrow, gameId);
    if (amount > d.amount) revert InsufficientBalance();
    uint avail = available(escrow, d.token);
    uint locked = restricted(escrow, d.token);
    if (amount == d.amount) {
      escrow.__accounts.remove(gameId);
    } else {
      escrow.__accounts.set(gameId, d.token, d.amount - amount);
    }
    escrow.__available.set(d.token, avail + amount);
    escrow.__restricted.set(d.token, locked - amount);
  }

  function release(EscrowAccount storage escrow, uint gameId) public {
    TokenDeposit memory d = account(escrow, gameId);
    release(escrow, gameId, d.amount);
  }
}

// Thin storage holder over the Escrow library. Inherited by the Lobby (and the escrow unit tests):
// keeps the per-player `__escrow` mapping plus thin wrappers with the original signatures, so call
// sites are unchanged while the heavy logic is linked out into the Escrow library.
abstract contract EscrowWrapper {
  using SafeERC20 for IERC20;
  using Escrow for Escrow.EscrowAccount;

  mapping(address => Escrow.EscrowAccount) internal __escrow;
  uint internal __platformFeePerc;

  function currentDeposit(address player, uint gameId) internal view returns (TokenDeposit memory) {
    return __escrow[player].account(gameId);
  }

  function tokens(address player) internal view returns (address[] memory) {
    return __escrow[player].tokens();
  }

  // TODO Phase 1 #(naming): rename to availableFunds; this is the withdrawable balance.
  function releasedFunds(address player, address token) internal view returns (uint) {
    return __escrow[player].available(token);
  }

  // TODO Phase 1 #7: shape decision pending — currently refund+withdraw, should be ledger-only.
  function refund(address player, uint gameId) internal {
    TokenDeposit memory d = __escrow[player].account(gameId);
    if (d.amount > 0) refund(player, gameId, d.amount);
  }

  // TODO Phase 1 #7: same; auto-withdraw shape pending.
  function refund(address player, uint gameId, uint amount) internal {
    TokenDeposit memory d = __escrow[player].account(gameId);
    if (amount > d.amount) revert Escrow.InsufficientBalance();
    __escrow[player].release(gameId, amount);
  }

  function refundExcess(address player, uint gameId, uint expected) internal {
    TokenDeposit memory d = __escrow[player].account(gameId);
    if (d.amount > expected) {
      refund(player, gameId, d.amount - expected);
    }
  }

  function _transfer(address receiver, uint amount, address token) private {
    if (token == address(0)) {
      (bool ok,) = payable(receiver).call{value: amount}("");
      if (!ok) revert Escrow.TransferFailed();
    } else {
      IERC20(token).safeTransfer(receiver, amount);
    }
  }

  function deposit(address player, uint amount, address token) internal {
    if (token == address(0)) {
      if (msg.value != amount) revert Escrow.InvalidDeposit();
    } else {
      IERC20(token).safeTransferFrom(player, address(this), amount);
    }
    __escrow[player].debit(amount, token);
  }

  function withdraw(address player, uint amount, address token) internal {
    uint avail = __escrow[player].available(token);
    if (amount > avail) revert Escrow.InsufficientBalance();
    _transfer(player, amount, token);
    __escrow[player].credit(amount, token);
  }

  function withdraw(address player, address token) internal {
    uint avail = __escrow[player].available(token);
    if (avail == 0) revert Escrow.InsufficientBalance();
    _transfer(player, avail, token);
    __escrow[player].credit(avail, token);
  }

  function lock(address player, uint gameId, uint amount, address token) internal {
    uint avail = __escrow[player].available(token);
    if (amount > avail) revert Escrow.InsufficientBalance();
    __escrow[player].lock(gameId, amount, token);
  }

  // TODO Phase 1 #7: same auto-withdraw shape concern as refund.
  function release(address player, uint gameId) internal {
    TokenDeposit memory d = __escrow[player].account(gameId);
    __escrow[player].release(gameId);
  }

  function disburse(
    address white,
    address black,
    uint gameId,
    IChessEngine.GameOutcome outcome
  ) internal {
    TokenDeposit memory wPrize = __escrow[white].account(gameId);
    TokenDeposit memory bPrize = __escrow[black].account(gameId);
    __escrow[white].release(gameId);
    __escrow[black].release(gameId);

    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      // Transfer black's stake -> white
      __escrow[white].debit(bPrize.amount, bPrize.token);
      __escrow[black].credit(bPrize.amount, bPrize.token);
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      // Transfer white's stake -> black
      __escrow[black].debit(wPrize.amount, wPrize.token);
      __escrow[white].credit(wPrize.amount, wPrize.token);
    } else if (outcome == IChessEngine.GameOutcome.Draw) {
      // Each side keeps its own stake — already released into their __available above.
    } else {
      revert Escrow.EscrowLocked();
    }
  }

  /*
   * Platform Funds
   */

  function _setPlatformFee(uint perc) internal {
    __platformFeePerc = perc;
  }

  function platformFeePerc() public view returns (uint) {
    return __platformFeePerc;
  }

  function _platformFee(uint wager) internal view returns (uint96) {
    return uint96(wager * __platformFeePerc / 100);
  }

  function chargeFee(address player, uint gameId, address token) internal {
    TokenDeposit memory d = __escrow[player].account(gameId);
    // No fees on zero-wager games
    if (d.amount == 0) return;
    uint96 fee = _platformFee(d.amount);
    __escrow[player].release(gameId, fee);             // restricted -> available
    __escrow[player].credit(fee, d.token);             // available -> (move out)
    __escrow[address(0)].debit(fee, d.token);          // (move into) platform pot
  }

  function releasePlatformFunds(uint amount, address token, address receiver) internal {
    uint balance = __escrow[address(0)].available(token);
    if (amount > balance) revert Escrow.InsufficientBalance();
    _transfer(receiver, amount, token);
    __escrow[address(0)].credit(amount, token);
  }

  function releasePlatformFunds(address token, address receiver) internal {
    uint balance = __escrow[address(0)].available(token);
    releasePlatformFunds(balance, token, receiver);
  }
}
