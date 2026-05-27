import {
  createPublicClient,
  createWalletClient,
  http,
  parseSignature,
  type Account,
  type Address,
  type Hash,
  type Hex,
  type WalletClient,
} from 'viem';
import { foundry, sepolia } from 'viem/chains';
import { hashAuthorization } from 'viem/utils';
import { privateKeyToAccount } from 'viem/accounts';

const RPC_URL = process.env.RPC_URL ?? 'http://127.0.0.1:8545';
const LOBBY_ADDRESS = process.env.LOBBY_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!LOBBY_ADDRESS) {
  throw new Error('LOBBY_ADDRESS env var is required');
}
if (!PRIVATE_KEY) {
  throw new Error('PRIVATE_KEY (relayer / gas sponsor) env var is required');
}

// The chain the server signs and submits for. CHAIN_ID must match the RPC (asserted at startup by
// assertChain) — a mismatch would produce 7702 authorizations / UserOps valid on the wrong chain.
const SUPPORTED_CHAINS = [foundry, sepolia];
const CHAIN_ID = Number(process.env.CHAIN_ID || foundry.id);
const chain = (() => {
  const c = SUPPORTED_CHAINS.find((x) => x.id === CHAIN_ID);
  if (!c) {
    throw new Error(
      `unsupported CHAIN_ID=${CHAIN_ID}; supported: ${SUPPORTED_CHAINS.map((x) => x.id).join(', ')}`,
    );
  }
  return c;
})();

// The server holds only this key: the relayer that sponsors gas (7702 setup txs + handleOps). It is
// never a game player — agents sign their own authorizations and UserOps and hold no ETH.
const account: Account = privateKeyToAccount(PRIVATE_KEY as `0x${string}`);

export const lobbyAddress = LOBBY_ADDRESS as Address;
export const relayerAddress = account.address;

// 7702 delegate target (Simple7702Account impl) + the EntryPoint agent UserOps run on.
export const ENTRY_POINT_V8 = '0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108' as Address;
export const entryPointAddress = (process.env.ENTRY_POINT as Address | undefined) ?? ENTRY_POINT_V8;
export const agentImpl = (process.env.AGENT_ACCOUNT as Address | undefined) ?? null;

// Reads target an explicit agent/player — the server has no default identity.
export function resolvePlayer(player?: Address): Address {
  if (!player) {
    throw new Error('a `player` (agent) address is required — the server has no default identity');
  }
  return player;
}

export const publicClient = createPublicClient({
  chain,
  transport: http(RPC_URL),
});

export const walletClient: WalletClient = createWalletClient({
  account,
  chain,
  transport: http(RPC_URL),
});

/*
 * EIP-7702 onboarding. The agent key (held by the agent, not the server) signs the authorization
 * digest; the relayer (PRIVATE_KEY) submits the type-4 setCode tx and pays gas.
 */

// A 7702 delegation designator is exactly `0xef0100 ++ impl` — 23 bytes (48 hex chars incl. 0x).
export async function agentDelegation(agent: Address): Promise<{ delegated: boolean; impl: Address | null }> {
  const code = await publicClient.getCode({ address: agent });
  if (!code || code.length !== 48 || !code.startsWith('0xef0100')) {
    return { delegated: false, impl: null };
  }
  return { delegated: true, impl: ('0x' + code.slice(8)) as Address };
}

// Round 1: the authorization hash the agent key must raw-sign (secp256k1 over the digest, not
// personal_sign). nonce is the agent's current account nonce (relayer ≠ authority, so no +1).
export async function buildDelegationAuth(agent: Address): Promise<{ digest: Hex; nonce: number }> {
  if (!agentImpl) throw new Error('AGENT_ACCOUNT (delegate impl) env var is required');
  const nonce = await publicClient.getTransactionCount({ address: agent });
  return { digest: hashAuthorization({ chainId: chain.id, contractAddress: agentImpl, nonce }), nonce };
}

// Round 2: assemble the signed authorization and broadcast the type-4 setCode tx via the relayer.
export async function submitDelegation(agent: Address, nonce: number, signature: Hex): Promise<Hash> {
  if (!agentImpl) throw new Error('AGENT_ACCOUNT (delegate impl) env var is required');
  const { r, s, yParity } = parseSignature(signature);
  const authorization = { address: agentImpl, chainId: chain.id, nonce, r, s, yParity: yParity ?? 0 };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (walletClient as any).sendTransaction({ authorizationList: [authorization], to: agent });
}

// Submit a tx, wait for inclusion, and return a compact receipt summary.
export async function submit(hash: Hash) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return {
    txHash: hash,
    blockNumber: receipt.blockNumber,
    status: receipt.status,
    gasUsed: receipt.gasUsed,
  };
}

// Guard against a misconfigured endpoint: the RPC must actually be the chain we sign for.
export async function assertChain(): Promise<void> {
  const actual = await publicClient.getChainId();
  if (actual !== chain.id) {
    throw new Error(
      `RPC chainId=${actual} does not match configured CHAIN_ID=${chain.id} (${chain.name})`,
    );
  }
}
