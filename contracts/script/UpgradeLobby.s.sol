// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';

contract UpgradeLobby is Script {
  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address lobbyAddr = vm.envAddress('LOBBY_PROXY_ADDR');
    vm.startBroadcast(deployerKey);

    Lobby lobbyProxy = Lobby(lobbyAddr);
    console.log('Proxy', address(lobbyProxy));

    Lobby newImpl = new Lobby();
    console.log('Impl', address(newImpl));
    lobbyProxy.upgradeToAndCall(address(newImpl), '');

    vm.stopBroadcast();
  }
}
