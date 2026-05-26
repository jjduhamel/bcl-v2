import { z } from 'zod';
import {
  concatHex,
  decodeAbiParameters,
  encodeAbiParameters,
  encodeFunctionData,
  toHex,
  type Abi,
  type Address,
  type Hex,
} from 'viem';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { lobbyAddress, relayerAddress, submit, walletClient } from './chain.js';
import { entryPoint, entryPointAbi } from './contracts/entryPoint.js';
import { errorResult, textResult } from './util.js';

const addressPattern = z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x-prefixed 40-hex address');
const hexPattern = z.string().regex(/^0x[a-fA-F0-9]+$/, 'must be 0x-prefixed hex');

// Two-round agent UserOp fields. Round 1 needs `sender` (the delegated agent); round 2 echoes the
// `userOp` from round 1 plus the agent's `signature` over the returned `userOpHash`.
export const agentOpFields = {
  sender: addressPattern.optional().describe('Agent EOA (UserOp sender). Required for the initial (unsigned) call.'),
  signature: hexPattern.optional().describe('65-byte hex signature of the round-1 `userOpHash` (round 2).'),
  userOp: hexPattern.optional().describe('Echoed `userOp` returned from round 1 (round 2).'),
};

// Engine functions the Lobby paymaster sponsors (mirrors Lobby._isSponsoredSelector).
const SPONSORED = new Set(['move', 'resign', 'offerDraw', 'respondDraw', 'claimVictory', 'disputeGame']);

// Fixed gas params for sponsored agent ops (phase 1, anvil). Refine to on-chain estimation later.
const VERIFICATION_GAS_LIMIT = 1_000_000n;
const CALL_GAS_LIMIT = 2_000_000n;
const PRE_VERIFICATION_GAS = 200_000n;
const POST_OP_GAS_LIMIT = 200_000n;
const MAX_PRIORITY_FEE_PER_GAS = 1_000_000_000n; // 1 gwei
const MAX_FEE_PER_GAS = 2_000_000_000n; // 2 gwei

const executeAbi = [
  {
    type: 'function',
    name: 'execute',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'target', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'data', type: 'bytes' },
    ],
    outputs: [],
  },
] as const;

// PackedUserOperation tuple — used to ABI-encode the round-1 op so the caller echoes it back in round 2.
const packedUserOpParams = [
  {
    type: 'tuple',
    components: [
      { name: 'sender', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'initCode', type: 'bytes' },
      { name: 'callData', type: 'bytes' },
      { name: 'accountGasLimits', type: 'bytes32' },
      { name: 'preVerificationGas', type: 'uint256' },
      { name: 'gasFees', type: 'bytes32' },
      { name: 'paymasterAndData', type: 'bytes' },
      { name: 'signature', type: 'bytes' },
    ],
  },
] as const;

interface PackedUserOp {
  sender: Address;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: bigint;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
}

// A uint256 packed as two left-padded uint128 halves (hi << 128 | lo) → bytes32.
function pack(hi: bigint, lo: bigint): Hex {
  return toHex((hi << 128n) | lo, { size: 32 });
}

export interface AgentOpArgs {
  sender?: Address;
  signature?: Hex;
  userOp?: Hex;
}

export interface EngineCallSpec {
  engine: Address;
  abi: Abi;
  functionName: string;
  args: readonly unknown[];
}

async function buildUserOp(sender: Address, spec: EngineCallSpec): Promise<PackedUserOp> {
  const inner = encodeFunctionData({ abi: spec.abi, functionName: spec.functionName, args: spec.args });
  const callData = encodeFunctionData({ abi: executeAbi, functionName: 'execute', args: [spec.engine, 0n, inner] });
  const nonce = (await entryPoint.read.getNonce([sender, 0n])) as bigint;
  return {
    sender,
    nonce,
    initCode: '0x',
    callData,
    accountGasLimits: pack(VERIFICATION_GAS_LIMIT, CALL_GAS_LIMIT),
    preVerificationGas: PRE_VERIFICATION_GAS,
    gasFees: pack(MAX_PRIORITY_FEE_PER_GAS, MAX_FEE_PER_GAS),
    paymasterAndData: concatHex([lobbyAddress, toHex(VERIFICATION_GAS_LIMIT, { size: 16 }), toHex(POST_OP_GAS_LIMIT, { size: 16 })]),
    signature: '0x',
  };
}

// The 7702-only write funnel. Every agent action is a sponsored UserOp: round 1 builds it and returns
// the `userOpHash` for the agent to raw-sign; round 2 attaches the signature and the relayer submits
// EntryPoint.handleOps (paying gas; the Lobby paymaster reimburses it). Non-sponsored calls (e.g. Lobby
// actions) are rejected up front.
export async function submitUserOp(args: AgentOpArgs, spec: EngineCallSpec): Promise<CallToolResult> {
  if (!SPONSORED.has(spec.functionName)) {
    return errorResult(
      `'${spec.functionName}' is not sponsorable under the 7702-only path (only whitelisted engine moves are). Perform it from an owner wallet / the frontend.`,
    );
  }

  if (args.signature) {
    if (!args.userOp) return errorResult('`userOp` (echoed from round 1) is required for the signed (round 2) call');
    const [op] = decodeAbiParameters(packedUserOpParams, args.userOp) as unknown as [PackedUserOp];
    op.signature = args.signature;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hash = await (walletClient as any).writeContract({
      address: entryPoint.address,
      abi: entryPointAbi,
      functionName: 'handleOps',
      args: [[op], relayerAddress],
    });
    return textResult(await submit(hash));
  }

  if (!args.sender) return errorResult('`sender` (the agent EOA) is required for the initial (unsigned) call');
  const op = await buildUserOp(args.sender, spec);
  const userOpHash = (await entryPoint.read.getUserOpHash([op])) as Hex;
  const userOp = encodeAbiParameters(packedUserOpParams, [op]);
  return textResult({ needsSignature: true, userOpHash, userOp });
}
