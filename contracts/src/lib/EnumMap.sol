// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz/utils/structs/EnumerableMap.sol';
import '@oz/utils/structs/EnumerableSet.sol';
import './SharedStructs.sol';

// Companion to OZ's EnumerableMap. Every map prunes a key whose value reaches zero, so
// keys()/length()/at() enumerate only live entries and get() of an absent key returns the type's
// zero. AddressUintMap holds unsigned values; AddressIntMap holds signed (two's-complement) values;
// UintTokenDepositMap maps a uint key to a packed TokenDeposit (token | amount), pruning when the
// amount is zero. Each is a single-field wrap, so storage layout matches the bare OZ map and an
// existing slot can be retyped across a UUPS upgrade.
library EnumMap {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.UintToBytes32Map;
  using EnumerableSet for EnumerableSet.AddressSet;

  error AmountOverflow();

  /* ---------- AddressUintMap: unsigned, prunes zero-valued keys ---------- */

  struct AddressUintMap {
    EnumerableMap.AddressToUintMap _inner;
  }

  function set(AddressUintMap storage m, address key, uint value) internal {
    if (value == 0) m._inner.remove(key);
    else m._inner.set(key, value);
  }

  function get(AddressUintMap storage m, address key) internal view returns (uint) {
    (bool ok, uint v) = m._inner.tryGet(key);
    return ok ? v : 0;
  }

  function add(AddressUintMap storage m, address key, uint value) internal {
    uint cur = get(m, key);
    set(m, key, cur + value);
  }

  function sub(AddressUintMap storage m, address key, uint value) internal {
    uint cur = get(m, key);
    set(m, key, cur - value);
  }

  function contains(AddressUintMap storage m, address key) internal view returns (bool) {
    return m._inner.contains(key);
  }

  function keys(AddressUintMap storage m) internal view returns (address[] memory) {
    return m._inner.keys();
  }

  function length(AddressUintMap storage m) internal view returns (uint) {
    return m._inner.length();
  }

  function at(AddressUintMap storage m, uint i) internal view returns (address, uint) {
    return m._inner.at(i);
  }

  /* ---------- AddressIntMap: signed (two's-complement), prunes zero-valued keys ---------- */

  struct AddressIntMap {
    EnumerableMap.AddressToUintMap _inner;
  }

  function set(AddressIntMap storage m, address key, int value) internal {
    if (value == 0) m._inner.remove(key);
    else m._inner.set(key, uint(value));
  }

  function get(AddressIntMap storage m, address key) internal view returns (int) {
    (bool ok, uint v) = m._inner.tryGet(key);
    return ok ? int(v) : int(0);
  }

  function add(AddressIntMap storage m, address key, int value) internal {
    int cur = get(m, key);
    set(m, key, cur + value);
  }

  function sub(AddressIntMap storage m, address key, int value) internal {
    int cur = get(m, key);
    set(m, key, cur - value);
  }

  function add(AddressIntMap storage m, address key, uint value) internal {
    add(m, key, int(value));
  }

  function sub(AddressIntMap storage m, address key, uint value) internal {
    sub(m, key, int(value));
  }

  function contains(AddressIntMap storage m, address key) internal view returns (bool) {
    return m._inner.contains(key);
  }

  function keys(AddressIntMap storage m) internal view returns (address[] memory) {
    return m._inner.keys();
  }

  function length(AddressIntMap storage m) internal view returns (uint) {
    return m._inner.length();
  }

  function at(AddressIntMap storage m, uint i) internal view returns (address, int) {
    (address k, uint v) = m._inner.at(i);
    return (k, int(v));
  }

  /* ---------- UintTokenDepositMap: uint key -> TokenDeposit, token|amount packed into bytes32 ---------- */

  struct UintTokenDepositMap {
    EnumerableMap.UintToBytes32Map _inner;
  }

  function _encodeTD(address token, uint96 amount) private pure returns (bytes32) {
    return bytes32((uint256(uint160(token)) << 96) | uint256(amount));
  }

  function _decodeTD(bytes32 val) private pure returns (TokenDeposit memory) {
    return TokenDeposit(address(uint160(uint256(val) >> 96)), uint96(uint256(val)));
  }

  function set(UintTokenDepositMap storage m, uint key, address token, uint amount) internal {
    if (amount > type(uint96).max) revert AmountOverflow();
    if (amount == 0) m._inner.remove(key);
    else m._inner.set(key, _encodeTD(token, uint96(amount)));
  }

  function get(UintTokenDepositMap storage m, uint key) internal view returns (TokenDeposit memory) {
    (bool ok, bytes32 val) = m._inner.tryGet(key);
    return ok ? _decodeTD(val) : TokenDeposit(address(0), 0);
  }

  function contains(UintTokenDepositMap storage m, uint key) internal view returns (bool) {
    return m._inner.contains(key);
  }

  function keys(UintTokenDepositMap storage m) internal view returns (uint[] memory) {
    return m._inner.keys();
  }

  function length(UintTokenDepositMap storage m) internal view returns (uint) {
    return m._inner.length();
  }

  function at(UintTokenDepositMap storage m, uint i) internal view returns (uint, TokenDeposit memory) {
    (uint key, bytes32 val) = m._inner.at(i);
    return (key, _decodeTD(val));
  }

  /* ---------- AddressEscrowStatsMap: address -> EscrowStats, append-only (stats never prune) ---------- */

  struct AddressEscrowStatsMap {
    EnumerableSet.AddressSet _keys;
    mapping(address => EscrowStats) _values;
  }

  // Returns a storage ref for in-place mutation, enrolling the key. Stats only ever grow, so keys
  // are never pruned — this keeps a token enumerable here after its balances prune to zero elsewhere.
  function stats(AddressEscrowStatsMap storage m, address key) internal returns (EscrowStats storage) {
    m._keys.add(key);
    return m._values[key];
  }

  function get(AddressEscrowStatsMap storage m, address key) internal view returns (EscrowStats memory) {
    return m._values[key];
  }

  function contains(AddressEscrowStatsMap storage m, address key) internal view returns (bool) {
    return m._keys.contains(key);
  }

  function keys(AddressEscrowStatsMap storage m) internal view returns (address[] memory) {
    return m._keys.values();
  }

  function length(AddressEscrowStatsMap storage m) internal view returns (uint) {
    return m._keys.length();
  }

  function at(AddressEscrowStatsMap storage m, uint i) internal view returns (address, EscrowStats memory) {
    address key = m._keys.at(i);
    return (key, m._values[key]);
  }
}
