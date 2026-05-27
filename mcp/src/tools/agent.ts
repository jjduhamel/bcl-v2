import { z } from 'zod';
import type { Address, Hex } from 'viem';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { lobby } from '../contracts/lobby.js';
import { agentDelegation, agentImpl, buildDelegationAuth, submit, submitDelegation } from '../chain.js';
import { errorResult, textResult, tool } from '../util.js';

const addressSchema = z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x-prefixed 40-hex address');
const hexSchema = z.string().regex(/^0x[a-fA-F0-9]+$/, 'must be 0x-prefixed hex');

export function registerAgentTools(server: McpServer) {
  tool(server,
    'agent_status',
    {
      title: 'Agent registration + delegation status',
      description:
        'Whether an agent EOA is registered in the Lobby (owner set) and 7702-delegated to the AgentAccount impl.',
      inputSchema: { agent: addressSchema },
    },
    async ({ agent }) => {
      const a = agent as Address;
      const owner = (await lobby.read.ownerOf([a])) as Address;
      const { delegated, impl } = await agentDelegation(a);
      return textResult({
        agent: a,
        owner,
        registered: owner.toLowerCase() !== a.toLowerCase(),
        delegated,
        impl,
      });
    },
  );

  tool(server,
    'delegate_agent',
    {
      title: 'Delegate an agent EOA (EIP-7702)',
      description:
        'Two-round. Round 1 (just `agent`): returns the EIP-7702 authorization `digest` the agent key must raw-sign (secp256k1 over the digest — not personal_sign) plus the `nonce` to echo. Round 2 (`agent` + `signature` + `nonce`): the server relayer submits the type-4 setCode tx, sponsoring gas, delegating the agent to the AgentAccount impl. Idempotent — returns early if already delegated. The agent must already be registered in the Lobby (owner action) for the paymaster to sponsor it.',
      inputSchema: {
        agent: addressSchema,
        signature: hexSchema.optional().describe('65-byte hex signature of the round-1 digest (round 2).'),
        nonce: z.number().int().nonnegative().optional().describe('Echoed authorization nonce from round 1 (round 2).'),
      },
    },
    async ({ agent, signature, nonce }) => {
      const a = agent as Address;
      if (!agentImpl) return errorResult('AGENT_ACCOUNT (delegate impl) env var is required');

      const status = await agentDelegation(a);
      if (status.delegated) {
        return textResult({ agent: a, delegated: true, impl: status.impl, note: 'already delegated' });
      }

      if (!signature) {
        const { digest, nonce: n } = await buildDelegationAuth(a);
        return textResult({ needsSignature: true, agent: a, digest, nonce: n, impl: agentImpl });
      }

      if (nonce === undefined) {
        return errorResult('`nonce` (echoed from round 1) is required for the signed call');
      }
      const receipt = await submit(await submitDelegation(a, nonce, signature as Hex));
      const after = await agentDelegation(a);
      return textResult({ ...receipt, agent: a, delegated: after.delegated, impl: after.impl });
    },
  );
}
