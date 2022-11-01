// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';

contract DeployLobby is Script {
  function setUp() public {}

  function run() public {
    //uint deployer = vm.envUint('PRIVATE_KEY');
    //vm.startBroadcast(deployer)
    vm.broadcast();
    Lobby lobby = new Lobby();
    lobby.initialize();
    console.log('Lobby', address(lobby));
    address arbiter = lobby.arbiter();
    console.log('Arbiter', arbiter);
    lobby.allowChallenges(true);
    lobby.allowWagers(true);

    ChessEngine engine = new ChessEngine(address(lobby));
    console.log('ChessEngine', address(engine));
    lobby.setChessEngine(address(engine));
    vm.stopBroadcast();
  }
}
