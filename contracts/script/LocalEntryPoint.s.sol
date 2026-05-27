// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@src/Lobby.sol';
import '@aa/core/EntryPoint.sol';
import '@aa/interfaces/IEntryPoint.sol';

// Makes a fresh anvil ERC-4337-ready: places EntryPoint v0.8 and wires/funds the Lobby paymaster.
contract LocalEntryPoint is Script {
  address constant ENTRYPOINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

  function run() external {
    uint256 adminPk = vm.envUint('PRIVATE_KEY');
    Lobby lobby = Lobby(vm.envAddress('LOBBY_PROXY_ADDR'));

    vm.broadcast(adminPk);
    EntryPoint epLocal = new EntryPoint();

    // Mirror it to the canonical address Simple7702Account hardcodes (etch local, anvil_setCode live).
    bytes memory epCode = address(epLocal).code;
    vm.etch(ENTRYPOINT_V8, epCode);
    vm.rpc('anvil_setCode', string.concat('["', vm.toString(ENTRYPOINT_V8), '","', vm.toString(epCode), '"]'));

    vm.startBroadcast(adminPk);
    lobby.setEntryPoint(IEntryPoint(ENTRYPOINT_V8));
    lobby.depositToEntryPoint{ value: 1 ether }();
    lobby.allowChallenges(true);
    vm.stopBroadcast();
  }
}
