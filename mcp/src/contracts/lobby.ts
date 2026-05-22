import { createRequire } from 'node:module';
import { getContract, type Abi } from 'viem';
import { publicClient, walletClient, lobbyAddress } from '../chain.js';

// The ABI lives outside src/ (it's a Forge build artifact at repo/out/) so we
// load it via createRequire rather than a static `import ... with { type: 'json' }`
// — that keeps it outside tsc's rootDir without a codegen step. The cost is
// that viem can't infer typed reads/writes from a non-const ABI; tool modules
// cast results at the call site.
const require = createRequire(import.meta.url);
const { abi } = require('../../../out/Lobby.sol/Lobby.json') as { abi: Abi };

export const lobbyAbi = abi;

export const lobby = getContract({
  address: lobbyAddress,
  abi,
  client: { public: publicClient, wallet: walletClient },
});
