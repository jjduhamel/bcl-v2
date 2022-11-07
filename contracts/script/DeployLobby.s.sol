// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';

contract DeployLobby is Script {
  function setUp() public {}

  function run() public {
    vm.startBroadcast();

    // Deploy and configure the lobby
    Lobby lobby = new Lobby();
    lobby.initialize();
    console.log('Lobby', address(lobby));
    lobby.allowChallenges(true);
    lobby.allowWagers(true);

    // Deploy and configure chess engine
    ChessEngine engine = new ChessEngine(address(lobby));
    lobby.setChessEngine(address(engine));
    console.log('ChessEngine', lobby.currentEngine());

    // Configure the arbiter
    lobby.setArbiter(msg.sender);
    console.log('Arbiter', lobby.arbiter());

    vm.stopBroadcast();
  }
}
