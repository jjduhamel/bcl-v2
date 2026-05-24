import { createRequire } from 'node:module';
import { getContract, zeroAddress, type Abi, type Address } from 'viem';
import { publicClient } from '../chain.js';
import { lobby } from './lobby.js';

const require = createRequire(import.meta.url);
const { abi } = require('../../../out/ChessEngine.sol/ChessEngine.json') as { abi: Abi };

export const chessEngineAbi = abi;

// Read-only binding — writes go through writeAs() in chain.ts.
function makeEngine(address: Address) {
  return getContract({
    address,
    abi,
    client: { public: publicClient },
  });
}

export type ChessEngineContract = ReturnType<typeof makeEngine>;

// Older games stay pinned to the engine they were created with — never cache
// or assume `lobby.currentEngine()`. We do cache by engine address so distinct
// games on the same engine share a single contract instance.
const engineCache = new Map<Address, ChessEngineContract>();

export async function engineFor(gameId: bigint): Promise<ChessEngineContract> {
  const address = (await lobby.read.chessEngine([gameId])) as Address;
  if (!address || address === zeroAddress) {
    throw new Error(`MissingRecord: no engine registered for gameId=${gameId}`);
  }
  let engine = engineCache.get(address);
  if (!engine) {
    engine = makeEngine(address);
    engineCache.set(address, engine);
  }
  return engine;
}
