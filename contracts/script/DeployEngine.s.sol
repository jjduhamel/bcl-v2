// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';

contract DeployEngine is Script {
  function deployEngine() private returns (ChessEngine) {
    ChessEngine impl = new ChessEngine();
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), '');
    ChessEngine engine = ChessEngine(address(proxy));
    return engine;
  }

  function run() public {
    address lobbyAddr = vm.envAddress('LOCAL_LOBBY_ADDR');
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    vm.startBroadcast(deployerKey);
    Lobby lobby = Lobby(lobbyAddr);
    console.log('Lobby', address(lobby));
    ChessEngine engine = deployEngine();
    engine.initialize(address(lobby));
    lobby.setChessEngine(address(engine));
    console.log('Engine', lobby.currentEngine());
    vm.stopBroadcast();
  }
}
