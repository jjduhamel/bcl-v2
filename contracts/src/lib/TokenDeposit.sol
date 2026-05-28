pragma solidity >=0.4.22 <0.9.0;
import '@oz/utils/structs/EnumerableMap.sol';

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
