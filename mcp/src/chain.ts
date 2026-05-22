import { createPublicClient, createWalletClient, http, type Address, type Hash } from 'viem';
import { foundry } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

const RPC_URL = process.env.RPC_URL ?? 'http://127.0.0.1:8545';
const LOBBY_ADDRESS = process.env.LOBBY_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!LOBBY_ADDRESS) {
  throw new Error('LOBBY_ADDRESS env var is required');
}

if (!PRIVATE_KEY) {
  throw new Error('PRIVATE_KEY env var is required');
}

export const lobbyAddress = LOBBY_ADDRESS as Address;

const account = privateKeyToAccount(PRIVATE_KEY as `0x${string}`);

export const botAddress = account.address;

export const publicClient = createPublicClient({
  chain: foundry,
  transport: http(RPC_URL),
});

export const walletClient = createWalletClient({
  account,
  chain: foundry,
  transport: http(RPC_URL),
});

// Submit a tx, wait for inclusion, and return a compact receipt summary.
// All writes funnel through here so the response shape is uniform.
export async function submit(hash: Hash) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return {
    txHash: hash,
    blockNumber: receipt.blockNumber,
    status: receipt.status,
    gasUsed: receipt.gasUsed,
  };
}

// TODO: session-key delegation (option C from design). The current setup
// signs with a single PRIVATE_KEY env var; once the contract supports
// bounded delegated keys we can drop the chainId guard and accept
// scoped permissions on real networks.
export async function assertLocalChain(): Promise<void> {
  const chainId = await publicClient.getChainId();
  if (chainId !== foundry.id) {
    throw new Error(
      `bcl-mcp is localhost-only for now; got chainId=${chainId}, expected ${foundry.id} (anvil)`,
    );
  }
}
