// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';

contract DeployLobby is Script {
  function deployLobby(address admin) private returns (Lobby) {
    Lobby impl = new Lobby();
    bytes memory initData = abi.encodeCall(Lobby.initialize, (admin));
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    return Lobby(address(proxy));
  }

  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address admin = vm.addr(deployerKey);
    vm.startBroadcast(deployerKey);
    Lobby lobby = deployLobby(admin);
    console.log('Lobby', address(lobby));
    console.log('Admin', admin);
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    vm.stopBroadcast();
  }
}
