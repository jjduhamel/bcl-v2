// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz/utils/structs/EnumerableMap.sol';

abstract contract EscrowTellerERC20 is Initializable {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.UintToUintMap;

  uint __escrow_total_deposits;
  EscrowInfo[] __escrow_db;
  mapping(address => EnumerableMap.UintToUintMap) __escrow_locked;
  mapping(address => EnumerableMap.AddressToUintMap) __escrow_available;

  enum EscrowStatus { Locked, Unlocked, Withdrew }

  struct EscrowInfo {
    address token;
    uint amount;
  }

  function __escrow_init() internal onlyInitializing {
  }

  function escrowDeposits(address player, address token) internal
  returns (uint[2][] memory) {
    EnumerableMap.UintToUintMap storage deposits = __escrow_locked[player];
    uint[2][] memory out = new uint[2][](deposits.length());
    for (uint j=0; j<deposits.length(); j++) {
      (out[0][j],out[1][j]) = deposits.at(j);
    }
    return out;
  }

  /*
  function escrowDeposit(uint gameId, address player, address token, uint amount) internal
  {
    __escrow_locked[player].set(gameId, amount);
  }

  function escrowUnlock(uint gameId, address player, address token, uint amount) internal
  {
    return __escrow_locked[player].set(gameId);
  }
  */
}
