// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import '@forge/Script.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';
import '@src/Paymaster.sol';
import '@aa/interfaces/IEntryPoint.sol';

// Tops up the standalone paymaster's EntryPoint deposit. Split from Deploy so it can be re-run to refund.
// Targets the deterministic Lobby proxy (recomputed from the same SALT as Deploy), so it tracks the
// current bytecode without a stale env address. Requires the EntryPoint to exist (canonical on live
// chains; on anvil run LocalEntryPoint.s.sol first).
contract FundEntryPoint is Script {
  bytes32 constant SALT = keccak256('bcl-v2.deterministic.v1'); // must match Deploy.s.sol
  address constant ENTRYPOINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

  function run() external {
    uint256 deployerKey = vm.envUint('PRIVATE_KEY');
    address admin = vm.addr(deployerKey);

    address lobbyImpl = vm.computeCreate2Address(SALT, keccak256(type(Lobby).creationCode), CREATE2_FACTORY);
    bytes memory lobbyInit = abi.encodeCall(Lobby.initialize, (admin));
    bytes32 proxyInitHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(lobbyImpl, lobbyInit))
    );
    Lobby lobby = Lobby(vm.computeCreate2Address(SALT, proxyInitHash, CREATE2_FACTORY));
    bytes32 paymasterInitHash = keccak256(
      abi.encodePacked(type(Paymaster).creationCode, abi.encode(lobby, IEntryPoint(ENTRYPOINT_V8)))
    );
    Paymaster paymaster = Paymaster(vm.computeCreate2Address(SALT, paymasterInitHash, CREATE2_FACTORY));
    console.log('Funding paymaster:', address(paymaster));

    string memory input = vm.prompt('EntryPoint deposit in wei (blank = 0.1 ETH)');
    uint256 deposit = bytes(input).length == 0 ? 0.1 ether : vm.parseUint(input);

    vm.startBroadcast(deployerKey);
    paymaster.depositToEntryPoint{ value: deposit }();
    vm.stopBroadcast();

    console.log('EntryPoint deposit:', paymaster.entryPointDeposit());
  }
}
