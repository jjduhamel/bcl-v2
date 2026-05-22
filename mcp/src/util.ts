import type { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

// JSON.stringify can't serialize bigint natively. Convert at this single
// boundary so internal math stays bigint everywhere upstream.
export function bigJSON(value: unknown): string {
  return JSON.stringify(value, (_, v) => (typeof v === 'bigint' ? v.toString() : v), 2);
}

export function textResult(value: unknown): CallToolResult {
  return { content: [{ type: 'text', text: bigJSON(value) }] };
}

export function errorResult(message: string): CallToolResult {
  return { content: [{ type: 'text', text: message }], isError: true };
}

// Thin wrapper around server.registerTool. The SDK's registerTool overloads
// thread the inputSchema's zod shape through z.infer + viem return types and
// blow tsc's instantiation budget on a few of our tools (TS2589). Casting to
// any inside the helper lets tsc pick the runtime overload without elaborating
// the deep generic chain at every call site — handlers still get the
// statically-typed Args we declare here.
type ZodShape = Record<string, z.ZodTypeAny>;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function tool<Args = any>(
  server: McpServer,
  name: string,
  meta: { title?: string; description?: string; inputSchema?: ZodShape },
  handler: (args: Args) => Promise<CallToolResult>,
): void {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (server as any).registerTool(name, meta, handler);
}
