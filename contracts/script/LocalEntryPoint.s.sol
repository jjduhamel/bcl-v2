// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@aa/core/EntryPoint.sol';

// Places EntryPoint v0.8 at its canonical address on a fresh anvil (it already exists on live
// chains). Run before Deploy.s.sol so the Lobby's paymaster funding has an EntryPoint to reach.
contract LocalEntryPoint is Script {
  address constant ENTRYPOINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

  function run() external {
    uint256 adminPk = vm.envUint('PRIVATE_KEY');

    vm.broadcast(adminPk);
    EntryPoint epLocal = new EntryPoint();

    // Mirror the code to the address Simple7702Account hardcodes (etch local sim, anvil_setCode
    // persists it on the running node).
    bytes memory epCode = address(epLocal).code;
    vm.etch(ENTRYPOINT_V8, epCode);
    vm.rpc('anvil_setCode', string.concat('["', vm.toString(ENTRYPOINT_V8), '","', vm.toString(epCode), '"]'));
  }
}
