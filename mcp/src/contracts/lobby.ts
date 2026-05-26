import { createRequire } from 'node:module';
import { getContract, type Abi } from 'viem';
import { publicClient, lobbyAddress } from '../chain.js';

// The ABI lives outside src/ (it's a Forge build artifact at repo/out/) so we
// load it via createRequire rather than a static `import ... with { type: 'json' }`
// — that keeps it outside tsc's rootDir without a codegen step. The cost is
// that viem can't infer typed reads/writes from a non-const ABI; tool modules
// cast results at the call site.
const require = createRequire(import.meta.url);
const { abi } = require('../../../out/Lobby.sol/Lobby.json') as { abi: Abi };

export const lobbyAbi = abi;

// Read-only binding. Engine actions go through the 7702 UserOp funnel (userop.ts); Lobby writes are
// owner-side and not sponsored.
export const lobby = getContract({
  address: lobbyAddress,
  abi,
  client: { public: publicClient },
});
