#!/usr/bin/env node
// Dev wrapper: load mcp/.env, validate required vars, exec tsx against
// src/index.ts. All config comes from the env file — no derivation from
// .mnemonic or broadcast artifacts.

import { existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { privateKeyToAccount } from 'viem/accounts';

const HERE = dirname(fileURLToPath(import.meta.url));
const MCP = resolve(HERE, '..');
const ENV_FILE = resolve(MCP, '.env');

if (!existsSync(ENV_FILE)) {
  console.error(`[dev] missing ${ENV_FILE} — copy mcp/.env.example to mcp/.env and fill it in.`);
  process.exit(1);
}
process.loadEnvFile(ENV_FILE);

const missing = ['PRIVATE_KEY', 'LOBBY_ADDRESS'].filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`[dev] ${ENV_FILE} is missing: ${missing.join(', ')}`);
  process.exit(1);
}

const botAddress = privateKeyToAccount(process.env.PRIVATE_KEY).address;
console.error(`[dev] bot=${botAddress} lobby=${process.env.LOBBY_ADDRESS}`);

const tsxBin = resolve(MCP, 'node_modules/.bin/tsx');
const child = spawn(tsxBin, [resolve(MCP, 'src/index.ts')], { stdio: 'inherit' });
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});
