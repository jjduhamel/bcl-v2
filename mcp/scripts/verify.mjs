#!/usr/bin/env node
// End-to-end verification of the 7702-only MCP server. The agent (an ephemeral key, generated here)
// onboards and plays through the MCP tools; the relayer/owner and opponent act directly via viem.
//
// Run prerequisites:
//   * anvil --hardfork prague on :8545 with the repo's .mnemonic
//   * Lobby + ChessEngine deployed and the EntryPoint placed + paymaster funded (yarn deploy:local)
//   * env: LOBBY_ADDRESS, AGENT_ACCOUNT (Simple7702Account impl), RPC_URL (loaded from mcp/.env if present)

import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import dotenv from 'dotenv';
import { createPublicClient, createWalletClient, getContract, http, zeroAddress } from 'viem';
import { foundry } from 'viem/chains';
import { generatePrivateKey, mnemonicToAccount, privateKeyToAccount, sign } from 'viem/accounts';

const HERE = dirname(fileURLToPath(import.meta.url));
const MCP = resolve(HERE, '..');
const REPO = resolve(MCP, '..');

dotenv.config({ path: resolve(MCP, '.env'), quiet: true });

const RPC_URL = process.env.RPC_URL ?? 'http://127.0.0.1:8545';
const LOBBY_ADDRESS = process.env.LOBBY_ADDRESS;
const AGENT_ACCOUNT = process.env.AGENT_ACCOUNT;
if (!LOBBY_ADDRESS || !AGENT_ACCOUNT) {
  console.error('verify: LOBBY_ADDRESS and AGENT_ACCOUNT are required (set them or fill mcp/.env)');
  process.exit(1);
}

const MNEMONIC = readFileSync(resolve(REPO, '.mnemonic'), 'utf8').trim();
const LobbyAbi = JSON.parse(readFileSync(resolve(REPO, 'out/Lobby.sol/Lobby.json'), 'utf8')).abi;

const ownerAcct = mnemonicToAccount(MNEMONIC, { addressIndex: 0 }); // relayer + owner + admin
const ownerKey = `0x${Buffer.from(ownerAcct.getHdKey().privateKey).toString('hex')}`;
const oppAcct = mnemonicToAccount(MNEMONIC, { addressIndex: 1 });
const agentKey = generatePrivateKey();
const agent = privateKeyToAccount(agentKey).address;

console.log('owner/relayer:', ownerAcct.address);
console.log('opponent     :', oppAcct.address);
console.log('agent (eph.) :', agent);
console.log('lobby        :', LOBBY_ADDRESS);

const publicClient = createPublicClient({ chain: foundry, transport: http(RPC_URL) });
const ownerWallet = createWalletClient({ account: ownerAcct, chain: foundry, transport: http(RPC_URL) });
const oppWallet = createWalletClient({ account: oppAcct, chain: foundry, transport: http(RPC_URL) });
const lobby = getContract({ address: LOBBY_ADDRESS, abi: LobbyAbi, client: { public: publicClient } });

async function send(wallet, functionName, args) {
  const hash = await wallet.writeContract({ address: LOBBY_ADDRESS, abi: LobbyAbi, functionName, args });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') throw new Error(`${functionName} reverted`);
  return receipt;
}

// ── Spawn the MCP server with the relayer key ───────────────────────────────
const SERVER = resolve(MCP, 'dist/index.js');
const mcp = spawn(process.execPath, [SERVER], {
  env: { ...process.env, LOBBY_ADDRESS, AGENT_ACCOUNT, PRIVATE_KEY: ownerKey, RPC_URL },
  stdio: ['pipe', 'pipe', 'pipe'],
});
mcp.on('exit', (code, sig) => console.log(`[mcp] exited code=${code} sig=${sig}`));

// ── JSON-RPC over stdio (newline-delimited) ─────────────────────────────────
const pending = new Map();
let nextId = 1;
let buffer = '';
const DEBUG = process.env.VERIFY_DEBUG === '1';
mcp.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  let nl;
  while ((nl = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, nl);
    buffer = buffer.slice(nl + 1);
    if (!line.trim()) continue;
    if (DEBUG) console.error('[mcp:out]', line);
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id != null && pending.has(msg.id)) {
      const { resolve: res, reject: rej } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) rej(new Error(JSON.stringify(msg.error))); else res(msg.result);
    }
  }
});
mcp.stderr.on('data', (c) => process.stderr.write('[mcp:err] ' + c));

function rpc(method, params = {}) {
  const id = nextId++;
  return new Promise((res, rej) => {
    pending.set(id, { resolve: res, reject: rej });
    mcp.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); rej(new Error(`rpc timeout: ${method}`)); }
    }, 30000);
  });
}
function notify(method, params = {}) {
  mcp.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
}
async function callRaw(name, args = {}) {
  return rpc('tools/call', { name, arguments: args });
}
async function callTool(name, args = {}) {
  const result = await callRaw(name, args);
  const text = result.content?.[0]?.text ?? '';
  if (result.isError) throw new Error(`Tool ${name} error: ${text}`);
  try { return JSON.parse(text); } catch { return text; }
}
async function expect(cond, msg) {
  if (!cond) throw new Error(`assertion failed: ${msg}`);
  console.log(`  ✓ ${msg}`);
}

try {
  await new Promise((r) => setTimeout(r, 300));

  console.log('\n[1] handshake + tools');
  const init = await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'verify', version: '0.1.0' } });
  await expect(init.serverInfo?.name === 'bcl-mcp', 'serverInfo.name = bcl-mcp');
  notify('notifications/initialized');
  const { tools } = await rpc('tools/list', {});
  const names = tools.map((t) => t.name);
  await expect(['move', 'delegate_agent', 'agent_status'].every((n) => names.includes(n)), 'move/delegate_agent/agent_status registered');

  console.log('\n[2] owner registers the agent + allows challenges (direct viem)');
  await send(ownerWallet, 'allowChallenges', [true]);
  await send(ownerWallet, 'registerAgent', [agent, 'demo', '', '', '', '']);
  const status0 = await callTool('agent_status', { agent });
  await expect(status0.registered === true && status0.delegated === false, 'agent registered, not yet delegated');

  console.log('\n[3] delegate the agent via MCP (two-round 7702)');
  const d1 = await callTool('delegate_agent', { agent });
  await expect(d1.needsSignature === true && typeof d1.digest === 'string', 'round 1 returns an authorization digest');
  const dSig = await sign({ hash: d1.digest, privateKey: agentKey, to: 'hex' });
  const d2 = await callTool('delegate_agent', { agent, signature: dSig, nonce: d1.nonce });
  await expect(d2.delegated === true, 'round 2 delegated the agent');
  const status1 = await callTool('agent_status', { agent });
  await expect(status1.delegated === true && status1.impl.toLowerCase() === AGENT_ACCOUNT.toLowerCase(), 'agent_status: delegated to AgentAccount impl');

  console.log('\n[4] owner seats the agent (white) vs opponent; opponent accepts (direct viem)');
  const chReceipt = await send(ownerWallet, 'challenge', [agent, oppAcct.address, true, 3600n, 0n, zeroAddress]);
  const chLog = chReceipt.logs.find((l) => l.address.toLowerCase() === LOBBY_ADDRESS.toLowerCase());
  const gameId = BigInt(chLog.topics[1]);
  console.log(`  → gameId=${gameId}`);
  await send(oppWallet, 'acceptChallenge', [gameId]);
  const game = await callTool('get_game', { gameId: gameId.toString() });
  await expect(game.state === 'Started', `state=Started (got ${game.state})`);
  await expect(game.whitePlayer.toLowerCase() === agent.toLowerCase(), 'agent is white');
  await expect(game.currentMove.toLowerCase() === agent.toLowerCase(), 'agent to move');

  console.log('\n[5] agent plays e2e4 gaslessly via MCP (two-round UserOp)');
  const depositBefore = await lobby.read.entryPointDeposit();
  const m1 = await callTool('move', { gameId: gameId.toString(), uci: 'e2e4', sender: agent });
  await expect(m1.needsSignature === true && typeof m1.userOpHash === 'string', 'round 1 returns a userOpHash');
  const mSig = await sign({ hash: m1.userOpHash, privateKey: agentKey, to: 'hex' });
  const m2 = await callTool('move', { gameId: gameId.toString(), uci: 'e2e4', signature: mSig, userOp: m1.userOp });
  await expect(m2.status === 'success', `handleOps tx success (got ${m2.status})`);

  console.log('\n[6] sponsored move applied, agent holds no ETH, paymaster paid');
  const moves = await callTool('get_moves', { gameId: gameId.toString() });
  await expect(moves.moves.length === 1 && moves.moves[0] === 'e2e4', 'move log = [e2e4]');
  await expect((await publicClient.getBalance({ address: agent })) === 0n, 'agent balance == 0');
  const depositAfter = await lobby.read.entryPointDeposit();
  await expect(depositAfter < depositBefore, `Lobby EntryPoint deposit dropped (${depositBefore} → ${depositAfter})`);

  console.log('\n[7] Lobby write tools error under the 7702-only path');
  const declined = await callRaw('accept_challenge', { gameId: gameId.toString(), sender: agent });
  await expect(declined.isError === true && /not sponsorable/i.test(declined.content?.[0]?.text ?? ''), 'accept_challenge returns the documented error');

  console.log('\nALL CHECKS PASSED ✅');
  process.exit(0);
} catch (err) {
  console.error('\nVERIFICATION FAILED:', err.message);
  process.exit(1);
} finally {
  mcp.kill();
}
