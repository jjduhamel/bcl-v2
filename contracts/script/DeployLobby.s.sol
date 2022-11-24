// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import 'src/Lobby.sol';

contract DeployLobby is Script {
  function deployLobby() private returns (Lobby) {
    Lobby impl = new Lobby();
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), '');
    Lobby lobby = Lobby(address(proxy));
    lobby.initialize();
    return lobby;
  }

  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    vm.startBroadcast(deployerKey);
    Lobby lobby = deployLobby();
    console.log('Lobby', address(lobby));
    console.log('Arbiter', lobby.arbiter());
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    vm.stopBroadcast();
  }
}
