// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/token/ERC20/IERC20.sol';
import '@oz/token/ERC20/utils/SafeERC20.sol';
import '@oz/utils/Arrays.sol';
import '@oz/utils/math/Math.sol';
import '@oz/utils/math/SignedMath.sol';
import '../IChessEngine.sol';
import './TokenDeposit.sol';
import './EnumMap.sol';

library EscrowLib {
  using SafeERC20 for IERC20;
  using EnumMap for EnumMap.AddressUintMap;
  using EnumMap for EnumMap.AddressIntMap;
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
    EnumMap.AddressUintMap __locked;
    // token -> withdrawable balance (signed; negative == gas debt owed to the platform)
    EnumMap.AddressIntMap __unlocked;
    mapping(address => EscrowStats) __gross;
  }

  function account(EscrowAccount storage escrow, uint gameId) internal view returns (TokenDeposit memory) {
    return escrow.__accounts.get(gameId);
  }

  function accounts(EscrowAccount storage escrow) internal view returns (uint[] memory) {
    return escrow.__accounts.keys();
  }

  // Every token the account holds a position in: withdrawable (__unlocked) plus any held only as
  // locked stake (__locked) with nothing withdrawable.
  function tokens(EscrowAccount storage escrow) internal view returns (address[] memory) {
    uint a = escrow.__unlocked.length();
    address[] memory lockedKeys = escrow.__locked.keys();
    address[] memory out = new address[](a + lockedKeys.length);
    for (uint i = 0; i < a; i++) (out[i], ) = escrow.__unlocked.at(i);
    uint n = a;
    for (uint i = 0; i < lockedKeys.length; i++)
      if (!escrow.__unlocked.contains(lockedKeys[i])) out[n++] = lockedKeys[i];
    return Arrays.splice(out, 0, n);
  }

  function locked(EscrowAccount storage escrow, address token) internal view returns (uint) {
    return escrow.__locked.get(token);
  }

  function unlocked(EscrowAccount storage escrow, address token) internal view returns (int) {
    return escrow.__unlocked.get(token);
  }

  // Spendable balance — `available` clamped to zero (a gas-debt account can't spend its debt).
  function available(EscrowAccount storage escrow, address token) internal view returns (uint) {
    return uint(SignedMath.max(unlocked(escrow, token), 0));
  }

  function total(EscrowAccount storage escrow, address token) internal view returns (int) {
    return unlocked(escrow, token) + int(locked(escrow, token));
  }

  /*
   * Debit / credit - Increase or decrease available balance.  Needed to moving funds
   * between accounts.
   */

  // Debit increases this account's available balance.
  function debit(EscrowAccount storage escrow, uint amount, address token) internal {
    escrow.__unlocked.add(token, amount);
  }

  // Credit reduces this account's available balance, guarding against an overdraw.
  function credit(EscrowAccount storage escrow, uint amount, address token) internal {
    if (amount > available(escrow, token)) revert InsufficientBalance();
    escrow.__unlocked.sub(token, amount);
  }

  // Like credit but without the overdraw guard; the balance may go negative. Used to charge gas
  // (a negative balance is gas debt, recovered from the account's next ETH inflow) and to move a
  // loser's stake out of an account that may already carry gas debt.
  function unsafeCredit(EscrowAccount storage escrow, uint amount, address token) internal {
    escrow.__unlocked.sub(token, amount);
  }

  /*
   * Lock / release — move between __unlocked and __accounts (per-game restricted).
   */

  function lock(EscrowAccount storage escrow, uint gameId, uint amount, address token) internal {
    TokenDeposit memory d = account(escrow, gameId);
    uint total = d.amount + amount;
    if (amount > available(escrow, token)) revert InsufficientBalance();
    if (d.amount > 0 && d.token != token) revert InvalidToken();
    if (total > type(uint96).max) revert AmountOverflow();
    escrow.__accounts.set(gameId, token, total);
    escrow.__unlocked.sub(token, amount);
    escrow.__locked.add(token, amount);
  }

  function release(EscrowAccount storage escrow, uint gameId, uint amount) internal {
    TokenDeposit memory d = account(escrow, gameId);
    if (amount > d.amount) revert InsufficientBalance();
    escrow.__accounts.set(gameId, d.token, d.amount - amount);
    escrow.__unlocked.add(d.token, amount);
    escrow.__locked.sub(d.token, amount);
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

  function tokenDeposits(address account) internal view returns (address[] memory) {
    return __escrow[account].tokens();
  }

  function lockedBalance(address account, address token) internal view returns (uint) {
    return __escrow[account].locked(token);
  }

  function unlockedBalance(address account, address token) internal view returns (int) {
    return __escrow[account].unlocked(token);
  }

  function availableBalance(address account, address token) internal view returns (uint) {
    return __escrow[account].available(token);
  }

  function totalBalance(address account, address token) internal view returns (int) {
    return __escrow[account].total(token);
  }

  function escrowStats(address account, address token) public view
  returns (EscrowLib.EscrowStats memory) {
    return __escrow[account].__gross[token];
  }

  // Returns the deposit reduced by any gas debt skimmed to the platform — i.e. the prize to award.
  function _refund(address account, uint gameId, uint amount) internal returns (TokenDeposit memory) {
    TokenDeposit memory d = __escrow[account].account(gameId);
    if (d.token == address(0)) {
      d.amount -= uint96(_settleGasDebt(account, amount));
    }
    __escrow[account].release(gameId, amount);
    return d;
  }

  function _refund(address account, uint gameId) internal returns (TokenDeposit memory) {
    TokenDeposit memory d = __escrow[account].account(gameId);
    return (d.amount > 0) ? _refund(account, gameId, d.amount) : TokenDeposit(d.token, 0);
  }

  function _refundExcess(address account, uint gameId, uint expected) internal returns (TokenDeposit memory) {
    TokenDeposit memory d = __escrow[account].account(gameId);
    return (d.amount > expected) ? _refund(account, gameId, d.amount - expected) : TokenDeposit(d.token, 0);
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
      _settleGasDebt(account, amount);
    } else {
      IERC20(token).safeTransferFrom(account, address(this), amount);
    }
    __escrow[account].debit(amount, token);
    __escrow[account].__gross[token].deposits += amount;
    __escrow[address(0)].__gross[token].deposits += amount;
  }

  function _withdraw(address account, uint amount, address token) internal {
    __escrow[account].credit(amount, token);
    __escrow[account].__gross[token].withdrawals += amount;
    __escrow[address(0)].__gross[token].withdrawals += amount;
    _transfer(account, amount, token);
  }

  function _withdraw(address account, address token) internal {
    int avail = __escrow[account].unlocked(token);
    if (avail <= 0) return;     // nothing withdrawable (and never while in gas debt)
    _withdraw(account, uint(avail), token);
  }

  function _lock(address account, uint gameId, uint amount, address token) internal {
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
    int balance = unlockedBalance(account, token);
    if (balance < int(extra)) {
      // Player can complete ERC20 for own account here (ERC20 balance is never negative)
      if (account == msg.sender && token != address(0)) {
        _deposit(account, extra - uint(balance), token);
      }
    }

    // Lock extra amount to fulfill the required escrow
    _lock(account, gameId, extra, token);
  }


  function _award(address to, address from, TokenDeposit memory prize) internal {
    __escrow[to].debit(prize.amount, prize.token);
    __escrow[from].unsafeCredit(prize.amount, prize.token);
    __escrow[to].__gross[prize.token].earnings += prize.amount;
    __escrow[from].__gross[prize.token].losses += prize.amount;
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

  // Never reverts (postOp must not revert under ERC-4337). Charges the full cost+fee; the owner's
  // balance may go negative (gas debt), recovered from their next ETH inflow. The platform pot is
  // credited only the realized portion — it must hold real ETH. Gross stats book the full sponsored gas.
  function _chargeGas(address owner, uint cost) internal returns (uint charged) {
    uint fee = gasFee(cost);
    uint total = cost + fee;
    charged = Math.min(total, __escrow[owner].available(address(0)));   // realized → platform pot
    __escrow[owner].unsafeCredit(total, address(0));                    // full charge; may go negative
    if (charged > 0) __escrow[address(0)].debit(charged, address(0));
    // Gross stats book the full sponsored gas; the unreimbursed remainder lives as the debt.
    __escrow[owner].__gross[address(0)].gasFees += fee;
    __escrow[owner].__gross[address(0)].gas += cost;
    __escrow[address(0)].__gross[address(0)].gasFees += fee;
    __escrow[address(0)].__gross[address(0)].gas += cost;
  }

  // Route to the platform pot any gas debt that an increase in `account`'s ETH balance just covered.
  // Call after an ETH inflow, passing the ETH unlocked balance captured before. ETH only.
  function _settleGasDebt(address account, uint amount) private returns (uint) {
    int balance = unlockedBalance(account, address(0));
    if (balance >= 0) return 0;
    uint debt = Math.min(uint(-balance), amount);
    __escrow[address(0)].debit(debt, address(0));
    return debt;
  }

  function _releasePlatformFunds(uint amount, address token, address receiver) internal {
    __escrow[address(0)].credit(amount, token);
    __escrow[address(0)].__gross[token].withdrawals += amount;
    _transfer(receiver, amount, token);
  }

  function _releasePlatformFunds(address token, address receiver) internal {
    uint balance = __escrow[address(0)].available(token);
    _releasePlatformFunds(balance, token, receiver);
  }
}
