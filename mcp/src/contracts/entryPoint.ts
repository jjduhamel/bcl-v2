import { createRequire } from 'node:module';
import { getContract, type Abi } from 'viem';
import { publicClient, entryPointAddress } from '../chain.js';

// Full ABI for the canonical EntryPoint v0.8 (address 0x4337…108), vendored from the eth-infinitism
// account-abstraction submodule (contracts/lib/account-abstraction/deployments/ethereum/EntryPoint.json).
// Pinned here — not read from the regenerated Forge `out/` artifact — since we don't author this contract.
const require = createRequire(import.meta.url);
const abi = require('../../abi/EntryPoint.json') as Abi;

export const entryPointAbi = abi;

// Read-only binding (getUserOpHash / getNonce / balanceOf). handleOps is submitted as a relayer write
// through chain.ts.
export const entryPoint = getContract({
  address: entryPointAddress,
  abi,
  client: { public: publicClient },
});
