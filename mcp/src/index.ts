#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { assertLocalChain, botAddress, lobbyAddress } from './chain.js';
import { registerLobbyTools } from './tools/lobby.js';
import { registerGameTools } from './tools/game.js';

async function main() {
  // Fail fast on the wrong chain — server-held key is anvil-only for now.
  await assertLocalChain();

  const server = new McpServer({
    name: 'bcl-mcp',
    version: '0.1.0',
  });

  registerLobbyTools(server);
  registerGameTools(server);

  // Diagnostic line to stderr — stdout is reserved for JSON-RPC frames.
  console.log('\n\nbcl-mcp server connected:\n');
  console.log(`  agent = ${botAddress}`);
  console.log(`  lobby = ${lobbyAddress}\n`);

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error('bcl-mcp fatal:', err);
  process.exit(1);
});
