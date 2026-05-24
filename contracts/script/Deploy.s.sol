// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import '@aa/accounts/Simple7702Account.sol';

// Deterministic (CREATE2) deployment.
//
// Run under `forge script --broadcast`: Foundry routes every `new{salt}` through the
// canonical deterministic deployer at 0x4e59...b4956c, so each address is a pure function
// of (factory, salt, initcode) and is therefore identical on every chain. The Lobby proxy
// address additionally depends on the admin baked into its initializer, and `setChessEngine`
// must be called by that admin — so use the SAME deployer key on every chain (admin =
// deployer). The Engine proxy address depends on the Lobby proxy address, which is itself
// deterministic, so the whole graph is reproducible cross-chain.
contract Deploy is Script {
  bytes32 constant SALT = keccak256('bcl-v2.deterministic.v1');

  function run() public {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address admin = vm.addr(deployerKey);

    vm.startBroadcast(deployerKey);

    // Lobby: impl, then proxy (atomically initialized in the proxy constructor).
    Lobby lobbyImpl = new Lobby{ salt: SALT }();
    bytes memory lobbyInit = abi.encodeCall(Lobby.initialize, (admin));
    Lobby lobby = Lobby(address(new ERC1967Proxy{ salt: SALT }(address(lobbyImpl), lobbyInit)));

    // Engine: impl, then proxy initialized with the (deterministic) Lobby proxy address.
    ChessEngine engineImpl = new ChessEngine{ salt: SALT }();
    bytes memory engineInit = abi.encodeCall(ChessEngine.initialize, (address(lobby)));
    ChessEngine engine = ChessEngine(address(new ERC1967Proxy{ salt: SALT }(address(engineImpl), engineInit)));

    // Wire the engine into the lobby (caller is the admin == deployer).
    lobby.setChessEngine(address(engine));

    // Reused EIP-7702 account implementation — the delegation target for agent EOAs.
    Simple7702Account agentAccount = new Simple7702Account{ salt: SALT }();

    vm.stopBroadcast();

    console.log('Lobby impl   ', address(lobbyImpl));
    console.log('Lobby proxy  ', address(lobby));
    console.log('Engine impl  ', address(engineImpl));
    console.log('Engine proxy ', address(engine));
    console.log('AgentAccount ', address(agentAccount));
    console.log('Admin        ', admin);

    // The user-facing proxy address must equal the independently computed CREATE2 address,
    // proving the deploy went through the canonical factory (i.e. is chain-deterministic).
    bytes32 lobbyProxyInitHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(lobbyImpl), lobbyInit))
    );
    address expected = vm.computeCreate2Address(SALT, lobbyProxyInitHash, CREATE2_FACTORY);
    require(expected == address(lobby), 'lobby proxy not deterministic');
  }
}
