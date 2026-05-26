// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import '@aa/accounts/Simple7702Account.sol';
import '@aa/interfaces/IEntryPoint.sol';

// Deterministic (CREATE2) deployment.
contract Deploy is Script {
  bytes32 constant SALT = keccak256('bcl-v2.deterministic.v1');
  address constant ENTRYPOINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

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

    // Wire the paymaster's EntryPoint and open the lobby. Funding the deposit is FundEntryPoint.s.sol.
    lobby.setEntryPoint(IEntryPoint(ENTRYPOINT_V8));
    lobby.allowChallenges(true);
    lobby.allowWagers(true);

    vm.stopBroadcast();

    console.log('Admin:         ', admin);
    console.log('Contract:');
    console.log('  Lobby:       ', address(lobbyImpl));
    console.log('  Engine:      ', address(engineImpl));
    console.log('Proxy:');
    console.log('  Lobby:       ', address(lobby));
    console.log('  Engine:      ', address(engine));
    console.log('AgentAccount:  ', address(agentAccount));

    // The user-facing proxy address must equal the independently computed CREATE2 address,
    // proving the deploy went through the canonical factory
    bytes32 lobbyProxyInitHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(lobbyImpl), lobbyInit))
    );
    address expected = vm.computeCreate2Address(SALT, lobbyProxyInitHash, CREATE2_FACTORY);
    require(expected == address(lobby), 'Lobby proxy not deterministic');
  }
}
