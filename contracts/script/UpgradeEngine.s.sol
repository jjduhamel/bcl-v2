// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine_0_2_0.sol';
import '@src/ChessEngine_0_2_1.sol';

contract DeployEngine is Script {
  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address lobbyAddr = vm.envAddress('LOCAL_LOBBY_ADDR');
    vm.startBroadcast(deployerKey);

    Lobby lobby = Lobby(lobbyAddr);
    console.log('Lobby', address(lobby));

    address engineAddr = lobby.currentEngine();
    ChessEngine_0_2_0 engineProxy = ChessEngine_0_2_0(engineAddr);
    console.log('Proxy', address(engineProxy));

    ChessEngine_0_2_1 newEngineImpl = new ChessEngine_0_2_1();
    console.log('Impl', address(newEngineImpl));
    engineProxy.upgradeTo(address(newEngineImpl));
    vm.stopBroadcast();
  }
}
