import { z } from 'zod';
import {
  createPublicClient,
  createWalletClient,
  encodeFunctionData,
  http,
  keccak256,
  parseSignature,
  parseTransaction,
  recoverAddress,
  serializeTransaction,
  type Abi,
  type Account,
  type Address,
  type Hash,
  type Hex,
  type WalletClient,
} from 'viem';
import { foundry } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { errorResult, textResult } from './util.js';

const addressPattern = z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x-prefixed 40-hex address');
const hexPattern = z.string().regex(/^0x[a-fA-F0-9]+$/, 'must be 0x-prefixed hex');

// Fields every write tool exposes for the dev/prod signing flow. Dev mode
// ignores all three; prod uses `from` (round 1) or `signature` + `unsignedTx`
// (round 2). Spread into each write tool's inputSchema via `...signingFields`.
export const signingFields = {
  from: addressPattern.optional().describe('Tx sender. Required in production for the initial (unsigned) call.'),
  signature: hexPattern.optional().describe('65-byte hex signature of the round-1 digest. Required in production round 2.'),
  unsignedTx: hexPattern.optional().describe('Echoed `unsignedTx` returned from round 1. Required in production round 2.'),
};

const IS_PROD = process.env.NODE_ENV === 'production';

const RPC_URL = process.env.RPC_URL ?? 'http://127.0.0.1:8545';
const LOBBY_ADDRESS = process.env.LOBBY_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!LOBBY_ADDRESS) {
  throw new Error('LOBBY_ADDRESS env var is required');
}

let account: Account | null = null;

if (IS_PROD) {
  // Prod is multi-tenant: no server-level signing identity. Every request
  // carries its own actor.
  if (PRIVATE_KEY) {
    throw new Error('PRIVATE_KEY must not be set in production (NODE_ENV=production)');
  }
} else {
  if (!PRIVATE_KEY) {
    throw new Error('PRIVATE_KEY env var is required');
  }
  account = privateKeyToAccount(PRIVATE_KEY as `0x${string}`);
}

export const lobbyAddress = LOBBY_ADDRESS as Address;

// Null in prod — no default actor; read tools must take an explicit `player`,
// write tools require `from` in round 1.
export const botAddress: Address | null = account?.address ?? null;

// Read-tool helper: dev defaults to bot; prod requires the caller to supply
// `player` since there's no server-level identity.
export function resolvePlayer(player?: Address): Address {
  const addr = player ?? botAddress;
  if (!addr) {
    throw new Error('player address is required in production (no server-level bot)');
  }
  return addr;
}

export const publicClient = createPublicClient({
  chain: foundry,
  transport: http(RPC_URL),
});

export const walletClient: WalletClient | null = account
  ? createWalletClient({ account, chain: foundry, transport: http(RPC_URL) })
  : null;

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

// TODO: session-key delegation. Once Lobby gains setSessionKey + a per-action
// `principal` modifier, lift the chainId guard for proxy mode.
export async function assertLocalChain(): Promise<void> {
  const chainId = await publicClient.getChainId();
  if (chainId !== foundry.id) {
    throw new Error(
      `bcl-mcp is localhost-only for now; got chainId=${chainId}, expected ${foundry.id} (anvil)`,
    );
  }
}

/*
 * Prod-mode tx assembly. Round 1 returns a digest the caller signs externally;
 * round 2 attaches the signature and broadcasts. Stateless — the caller echoes
 * `unsignedTx` back in round 2.
 */

export interface BuildUnsignedTxInputs {
  from: Address;
  to: Address;
  abi: Abi;
  functionName: string;
  args: readonly unknown[];
  value?: bigint;
}

export async function buildUnsignedTx({
  from,
  to,
  abi,
  functionName,
  args,
  value = 0n,
}: BuildUnsignedTxInputs): Promise<{ unsignedTx: Hex; digest: Hex }> {
  const data = encodeFunctionData({ abi, functionName, args });
  const [nonce, fees, gas] = await Promise.all([
    publicClient.getTransactionCount({ address: from }),
    publicClient.estimateFeesPerGas(),
    publicClient.estimateGas({ account: from, to, data, value }),
  ]);
  const unsignedTx = serializeTransaction({
    type: 'eip1559',
    chainId: foundry.id,
    to,
    value,
    data,
    nonce,
    gas,
    maxFeePerGas: fees.maxFeePerGas,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
  });
  return { unsignedTx, digest: keccak256(unsignedTx) };
}

export async function assembleAndBroadcast({
  unsignedTx,
  signature,
}: {
  unsignedTx: Hex;
  signature: Hex;
}): Promise<{ hash: Hash; signer: Address }> {
  const tx = parseTransaction(unsignedTx);
  const sig = parseSignature(signature);
  const signedSerialized = serializeTransaction(tx, sig);
  const signer = await recoverAddress({ hash: keccak256(unsignedTx), signature });
  const hash = await publicClient.sendRawTransaction({ serializedTransaction: signedSerialized });
  return { hash, signer };
}

/*
 * Single funnel for every write tool. Dev signs locally with the configured
 * key; prod runs two rounds (no signature → return digest + unsignedTx; with
 * signature → attach, broadcast, return receipt). Dev mode ignores `from`,
 * `signature`, and `unsignedTx`.
 */

export interface WriteSpec {
  to: Address;
  abi: Abi;
  functionName: string;
  args: readonly unknown[];
  value?: bigint;
}

export interface WriteArgs {
  from?: Address;
  signature?: Hex;
  unsignedTx?: Hex;
}

export async function writeAs(args: WriteArgs, spec: WriteSpec): Promise<CallToolResult> {
  if (!IS_PROD) {
    // Dev mode.  Sign all transactions using embedded private key
    if (!walletClient) {
      return errorResult('walletClient unavailable in dev mode (PRIVATE_KEY missing?)');
    }

    // Create a signature with the embedded PRIVATE_KEY
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hash = await (walletClient as any).writeContract({
      address: spec.to,
      abi: spec.abi,
      functionName: spec.functionName,
      args: spec.args,
      value: spec.value,
    });

    return textResult(await submit(hash));
  } else if (args.signature) {
    // Stage 2, assemble signed tx and broadcast o contract
    if (!args.unsignedTx) {
      return errorResult('`unsignedTx` is required for the signed (round 2) call');
    }

    const { hash, signer } = await assembleAndBroadcast({
      unsignedTx: args.unsignedTx,
      signature: args.signature,
    });

    return textResult({ ...(await submit(hash)), signer });
  } else {
    // Stage 1, construct unsigned tx
    if (!args.from) {
      return errorResult('`from` is required in production for the initial (unsigned) call');
    }


    const { unsignedTx, digest } = await buildUnsignedTx({
      from: args.from,
      to: spec.to,
      abi: spec.abi,
      functionName: spec.functionName,
      args: spec.args,
      value: spec.value,
    });

    return textResult({ needsSignature: true, digest, unsignedTx });
  }
  }
}
