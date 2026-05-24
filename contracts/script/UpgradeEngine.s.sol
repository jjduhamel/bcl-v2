// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';

contract UpgradeEngine is Script {
  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address lobbyAddr = vm.envAddress('LOCAL_LOBBY_ADDR');
    vm.startBroadcast(deployerKey);

    Lobby lobby = Lobby(lobbyAddr);
    console.log('Lobby', address(lobby));

    address engineAddr = lobby.currentEngine();
    ChessEngine engineProxy = ChessEngine(engineAddr);
    console.log('Proxy', address(engineProxy));

    ChessEngine newImpl = new ChessEngine();
    console.log('Impl', address(newImpl));
    engineProxy.upgradeToAndCall(address(newImpl), '');
    vm.stopBroadcast();
  }
}
