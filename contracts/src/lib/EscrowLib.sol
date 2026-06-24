// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/token/ERC20/IERC20.sol';
import '@oz/token/ERC20/utils/SafeERC20.sol';
import '@oz/utils/Arrays.sol';
import '../IChessEngine.sol';
import './TokenDeposit.sol';
import './EnumMap.sol';

// Escrow accounting + custody as an external (linked) library: heavy EnumerableMap machinery is
// deployed once and delegatecall-linked out of the calling contract's bytecode. Every function runs
// in the caller's context (delegatecall preserves address(this) and msg.value), so funds and state
// live on the caller — `EscrowWrapper` below holds the per-player `EscrowAccount` mapping and
// exposes thin wrappers. Library is transfer-free: ERC20 transferFrom is performed by the wrapper.
library EscrowLib {
  using SafeERC20 for IERC20;
  using EnumMap for EnumMap.AddressUintMap;
  using EnumMap for EnumMap.UintTokenDepositMap;

  error EscrowLocked();
  error AmountOverflow();
  error InvalidDeposit();
  error InvalidToken();
  error InsufficientBalance();
  error TransferFailed();

  struct EscrowStats {
    uint deposits;
    uint withdrawals;
    uint wagers;
    uint earnings;
    uint losses;
    uint platformFees;
    uint gasFees;
    uint gas;
  }

  struct EscrowAccount {
    // gameId -> per-game locked deposit
    EnumMap.UintTokenDepositMap __accounts;
    // token -> total locked across games (cache of Σ __accounts; backs total/locked reads)
    EnumMap.AddressUintMap __restricted;
    // token -> withdrawable balance
    EnumMap.AddressUintMap __available;
    mapping(address => EscrowStats) __gross;
  }

  function account(EscrowAccount storage escrow, uint gameId) internal view returns (TokenDeposit memory) {
    return escrow.__accounts.get(gameId);
  }

  function accounts(EscrowAccount storage escrow) internal view returns (uint[] memory) {
    return escrow.__accounts.keys();
  }

  // Every token the account holds a position in: withdrawable (__available) plus any held only as
  // locked stake (__restricted) with nothing withdrawable.
  function tokens(EscrowAccount storage escrow) internal view returns (address[] memory) {
    uint a = escrow.__available.length();
    address[] memory locked = escrow.__restricted.keys();
    address[] memory out = new address[](a + locked.length);
    for (uint i = 0; i < a; i++) (out[i], ) = escrow.__available.at(i);
    uint n = a;
    for (uint i = 0; i < locked.length; i++)
      if (!escrow.__available.contains(locked[i])) out[n++] = locked[i];
    return Arrays.splice(out, 0, n);
  }

  function available(EscrowAccount storage escrow, address token) internal view returns (uint) {
    return escrow.__available.get(token);
  }

  function restricted(EscrowAccount storage escrow, address token) internal view returns (uint) {
    return escrow.__restricted.get(token);
  }

  function total(EscrowAccount storage escrow, address token) internal view returns (uint) {
    return available(escrow, token) + restricted(escrow, token);
  }

  /*
   * Debit / credit - Increase or decrease available balance.  Needed to moving funds
   * between accounts.
   */

  // Debit increases this account's available balance.
  function debit(EscrowAccount storage escrow, uint amount, address token) internal {
    uint avail = available(escrow, token);
    escrow.__available.set(token, avail + amount);
  }

  // Credit reduces this account's available balance.
  function credit(EscrowAccount storage escrow, uint amount, address token) internal {
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
    uint total = d.amount + amount;
    if (avail < amount) revert InsufficientBalance();
    if (d.amount > 0 && d.token != token) revert InvalidToken();
    if (total > type(uint96).max) revert AmountOverflow();
    escrow.__accounts.set(gameId, token, total);
    escrow.__available.set(token, avail - amount);
    escrow.__restricted.set(token, locked + amount);
  }

  function release(EscrowAccount storage escrow, uint gameId, uint amount) internal {
    TokenDeposit memory d = account(escrow, gameId);
    if (amount > d.amount) revert InsufficientBalance();
    uint avail = available(escrow, d.token);
    uint locked = restricted(escrow, d.token);
    escrow.__accounts.set(gameId, d.token, d.amount - amount);   // prunes when fully released
    escrow.__available.set(d.token, avail + amount);
    escrow.__restricted.set(d.token, locked - amount);
  }

  function release(EscrowAccount storage escrow, uint gameId) internal {
    TokenDeposit memory d = account(escrow, gameId);
    release(escrow, gameId, d.amount);
  }
}

// Thin storage holder over the Escrow library. Inherited by the Lobby (and the escrow unit tests):
// keeps the per-player `__escrow` mapping plus thin wrappers with the original signatures, so call
// sites are unchanged while the heavy logic is linked out into the Escrow library.
abstract contract EscrowWrapper {
  using SafeERC20 for IERC20;
  using EscrowLib for EscrowLib.EscrowAccount;

  mapping(address => EscrowLib.EscrowAccount) internal __escrow;
  uint internal __platformFeePerc;
  uint internal __gasSponsorFeePerc;

  // Reserved slots — decrement when adding state above to preserve layout across upgrades.
  uint256[47] private __gap;

  function currentDeposit(address account, uint gameId) internal view returns (TokenDeposit memory) {
    return __escrow[account].account(gameId);
  }

  // Withdrawable (unrestricted) balance.
  function availableFunds(address account, address token) internal view returns (uint) {
    return __escrow[account].available(token);
  }

  function totalBalance(address account, address token) internal view returns (uint) {
    return __escrow[account].total(token);
  }

  function tokens(address account) internal view returns (address[] memory) {
    return __escrow[account].tokens();
  }

  function escrowStats(address account, address token) public view
  returns (EscrowLib.EscrowStats memory) {
    return __escrow[account].__gross[token];
  }

  function _refund(address account, uint gameId) internal {
    TokenDeposit memory d = __escrow[account].account(gameId);
    if (d.amount > 0) _refund(account, gameId, d.amount);
  }

  function _refund(address account, uint gameId, uint amount) internal {
    TokenDeposit memory d = __escrow[account].account(gameId);
    if (amount > d.amount) revert EscrowLib.InsufficientBalance();
    __escrow[account].release(gameId, amount);
  }

  function _refundExcess(address account, uint gameId, uint expected) internal {
    TokenDeposit memory d = __escrow[account].account(gameId);
    if (d.amount > expected) {
      _refund(account, gameId, d.amount - expected);
    }
  }

  function _transfer(address receiver, uint amount, address token) private {
    if (token == address(0)) {
      (bool ok,) = payable(receiver).call{value: amount}("");
      if (!ok) revert EscrowLib.TransferFailed();
    } else {
      IERC20(token).safeTransfer(receiver, amount);
    }
  }

  function _deposit(address account, uint amount, address token) internal {
    if (account != msg.sender) revert EscrowLib.InvalidDeposit();

    if (token == address(0)) {
      if (msg.value != amount) revert EscrowLib.InvalidDeposit();
    } else {
      IERC20(token).safeTransferFrom(account, address(this), amount);
    }
    __escrow[account].debit(amount, token);
    __escrow[account].__gross[token].deposits += amount;
    __escrow[address(0)].__gross[token].deposits += amount;
  }

  function _withdraw(address account, uint amount, address token) internal {
    uint avail = __escrow[account].available(token);
    if (amount > avail) revert EscrowLib.InsufficientBalance();
    // CEI: state updates before the external transfer so a reentrant receiver
    // can't observe stale balance and double-spend.
    __escrow[account].credit(amount, token);
    __escrow[account].__gross[token].withdrawals += amount;
    __escrow[address(0)].__gross[token].withdrawals += amount;
    _transfer(account, amount, token);
  }

  function _withdraw(address account, address token) internal {
    uint avail = __escrow[account].available(token);
    if (avail == 0) revert EscrowLib.InsufficientBalance();
    _withdraw(account, avail, token);
  }

  function _lock(address account, uint gameId, uint amount, address token) internal {
    uint avail = __escrow[account].available(token);
    if (amount > avail) revert EscrowLib.InsufficientBalance();
    __escrow[account].lock(gameId, amount, token);
    __escrow[account].__gross[token].wagers += amount;
    __escrow[address(0)].__gross[token].wagers += amount;
  }

  // NOTE: account should be ownerOf(msg.sender)
  function _escrow(address account, uint gameId, uint amount, address token) internal {
    uint locked = currentDeposit(account, gameId).amount;
    if (locked >= amount) return;
    uint extra = amount-locked;

    // For ERC20, deposit any amount over available balance
    uint balance = availableFunds(account, token);
    if (balance < extra) {
      // Player can complete ERC20 for own account here
      if (account == msg.sender && token != address(0)) {
        _deposit(account, extra-balance, token);
      } else {
        revert EscrowLib.InsufficientBalance();
      }
    }

    // Lock extra amount to fulfill the required escrow
    _lock(account, gameId, extra, token);
  }

  function _disburse(
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
      // Update player stats
      __escrow[white].__gross[bPrize.token].earnings += bPrize.amount;
      __escrow[black].__gross[bPrize.token].losses += bPrize.amount;
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      // Transfer white's stake -> black
      __escrow[black].debit(wPrize.amount, wPrize.token);
      __escrow[white].credit(wPrize.amount, wPrize.token);
      // Update player stats
      __escrow[black].__gross[wPrize.token].earnings += wPrize.amount;
      __escrow[white].__gross[wPrize.token].losses += wPrize.amount;
    } else if (outcome == IChessEngine.GameOutcome.Draw) {
      // Each side keeps its own stake — already released into their __available above.
    } else {
      revert EscrowLib.EscrowLocked();
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

  function platformFee(uint wager) public view returns (uint96) {
    return uint96(wager * __platformFeePerc / 100);
  }

  function _chargeFee(address account, uint gameId, address token) internal {
    TokenDeposit memory d = __escrow[account].account(gameId);
    // No fees on zero-wager games
    if (d.amount == 0) return;
    uint96 fee = platformFee(d.amount);
    __escrow[account].release(gameId, fee);             // restricted -> available
    __escrow[account].credit(fee, d.token);             // available -> (move out)
    __escrow[address(0)].debit(fee, d.token);          // (move into) platform pot
    // Update escrow stats
    __escrow[account].__gross[token].platformFees += fee;
    __escrow[address(0)].__gross[token].platformFees += fee;
  }

  /*
   * Gas Fee
   */

  function _setGasFee(uint perc) internal {
    __gasSponsorFeePerc = perc;
  }

  function gasFeePerc() public view returns (uint) {
    return __gasSponsorFeePerc;
  }

  function gasFee(uint wager) public view returns (uint96) {
    return uint96(wager * __gasSponsorFeePerc / 100);
  }

  // Saturating: never reverts. Moves min(cost + fee, avail) ETH from owner.available → platform
  // pot. Saturation is required because postOp must not revert under ERC-4337.
  function _chargeGas(address owner, uint cost) internal returns (uint charged) {
    uint avail = __escrow[owner].available(address(0));
    uint fee = gasFee(cost);
    uint total = cost + fee;
    charged = total < avail ? total : avail;
    if (charged > 0) {
      __escrow[owner].credit(charged, address(0));
      __escrow[address(0)].debit(charged, address(0));
      // Update escrow stats
      __escrow[owner].__gross[address(0)].gasFees += fee;
      __escrow[owner].__gross[address(0)].gas += cost;
      __escrow[address(0)].__gross[address(0)].gasFees += fee;
      __escrow[address(0)].__gross[address(0)].gas += cost;
    }
  }

  function _releasePlatformFunds(uint amount, address token, address receiver) internal {
    uint balance = __escrow[address(0)].available(token);
    if (amount > balance) revert EscrowLib.InsufficientBalance();
    // CEI: see `withdraw` above.
    __escrow[address(0)].credit(amount, token);
    __escrow[address(0)].__gross[token].withdrawals += amount;
    _transfer(receiver, amount, token);
  }

  function _releasePlatformFunds(address token, address receiver) internal {
    uint balance = __escrow[address(0)].available(token);
    _releasePlatformFunds(balance, token, receiver);
  }
}
