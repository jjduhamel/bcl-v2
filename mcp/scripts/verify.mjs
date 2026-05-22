#!/usr/bin/env node
// End-to-end verification: spawn the MCP server over stdio, drive a complete
// game (opponent acts directly via viem, bot acts through MCP tool calls).
//
// Run prerequisites:
//   * anvil running on :8545 with the repo's .mnemonic
//   * Lobby + ChessEngine proxies deployed (LOBBY_ADDRESS hardcoded below
//     from broadcast/DeployLobby.s.sol/31337/run-latest.json)

import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createPublicClient, createWalletClient, getContract, http, parseGwei, toHex, zeroAddress } from 'viem';
import { foundry } from 'viem/chains';
import { mnemonicToAccount } from 'viem/accounts';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const MNEMONIC = readFileSync(resolve(REPO, '.mnemonic'), 'utf8').trim();
const LOBBY_ADDRESS = '0x1718896de70275f2967b288c5ab106a473a54782';
const LobbyAbi = JSON.parse(readFileSync(resolve(REPO, 'out/Lobby.sol/Lobby.json'), 'utf8')).abi;
const EngineAbi = JSON.parse(readFileSync(resolve(REPO, 'out/ChessEngine.sol/ChessEngine.json'), 'utf8')).abi;

function deriveAccount(addressIndex) {
  const acct = mnemonicToAccount(MNEMONIC, { addressIndex });
  return { account: acct, address: acct.address, key: toHex(acct.getHdKey().privateKey) };
}

const bot = deriveAccount(0);
const opp = deriveAccount(1);

console.log('Bot      :', bot.address);
console.log('Opponent :', opp.address);
console.log('Lobby    :', LOBBY_ADDRESS);

// ── Opponent's viem clients (talks to anvil directly) ───────────────────────
const publicClient = createPublicClient({ chain: foundry, transport: http() });
const oppWallet = createWalletClient({ account: opp.account, chain: foundry, transport: http() });
const lobby = getContract({
  address: LOBBY_ADDRESS,
  abi: LobbyAbi,
  client: { public: publicClient, wallet: oppWallet },
});

async function engineFor(gameId) {
  const addr = await lobby.read.chessEngine([gameId]);
  return getContract({ address: addr, abi: EngineAbi, client: { public: publicClient, wallet: oppWallet } });
}

// ── Spawn the MCP server with the bot key ───────────────────────────────────
const NODE = '/home/jjd/.local/share/mise/installs/node/22.22.3/bin/node';
const SERVER = resolve(HERE, '../dist/index.js');
const mcp = spawn(NODE, [SERVER], {
  env: { ...process.env, LOBBY_ADDRESS, PRIVATE_KEY: bot.key, RPC_URL: 'http://localhost:8545' },
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
  const body = JSON.stringify({ jsonrpc: '2.0', id, method, params });
  return new Promise((res, rej) => {
    pending.set(id, { resolve: res, reject: rej });
    mcp.stdin.write(body + '\n');
    setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); rej(new Error(`rpc timeout: ${method}`)); }
    }, 30000);
  });
}

function notify(method, params = {}) {
  mcp.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
}

async function callTool(name, args = {}) {
  const result = await rpc('tools/call', { name, arguments: args });
  const text = result.content?.[0]?.text ?? '';
  if (result.isError) throw new Error(`Tool ${name} error: ${text}`);
  // Most tools return JSON-stringified payloads; render_board returns raw text.
  try { return JSON.parse(text); } catch { return text; }
}

async function expect(cond, msg) {
  if (!cond) throw new Error(`assertion failed: ${msg}`);
  console.log(`  ✓ ${msg}`);
}

// ── Verification flow ───────────────────────────────────────────────────────
try {
  // Wait for the server to be ready (it prints to stderr after assertLocalChain).
  await new Promise((r) => setTimeout(r, 300));

  // 1. Handshake
  console.log('\n[1] initialize handshake');
  const init = await rpc('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'verify-driver', version: '0.1.0' },
  });
  await expect(init.serverInfo?.name === 'bcl-mcp', `serverInfo.name = bcl-mcp (got ${init.serverInfo?.name})`);
  notify('notifications/initialized');
  await new Promise((r) => setTimeout(r, 100));

  // 2. Tools list
  console.log('\n[2] tools/list');
  const toolsList = await rpc('tools/list', {});
  await expect(toolsList.tools.length === 27, `27 tools registered (got ${toolsList.tools.length})`);

  // 3. Read tool: lounge_stats
  console.log('\n[3] lounge_stats (read)');
  const stats = await callTool('lounge_stats');
  await expect(typeof stats.totalChallenges === 'string', 'totalChallenges serialized as string');

  // 4. Create a challenge from opponent → bot (no wager, 1h/move)
  console.log('\n[4] opponent creates challenge against bot');
  const challengeHash = await lobby.write.challenge([bot.address, true, 3600n, 0n, zeroAddress]);
  const receipt = await publicClient.waitForTransactionReceipt({ hash: challengeHash });
  await expect(receipt.status === 'success', 'challenge tx succeeded');
  // Decode the NewChallenge event to get gameId
  const newChallengeTopic = LobbyAbi.find((x) => x.type === 'event' && x.name === 'NewChallenge');
  const newChallengeLog = receipt.logs.find((l) => l.address.toLowerCase() === LOBBY_ADDRESS.toLowerCase());
  const gameId = BigInt(newChallengeLog.topics[1]); // gameId is the first indexed param
  console.log(`  → gameId=${gameId}`);

  // 5. Bot reads the challenge via MCP
  console.log('\n[5] bot lists pending challenges via MCP');
  const challenges = await callTool('list_challenges');
  const ids = challenges.challenges.map(BigInt);
  await expect(ids.includes(gameId), `gameId ${gameId} appears in bot's pending challenges`);

  // 6. Get the full game data
  console.log('\n[6] get_game (read)');
  const game = await callTool('get_game', { gameId: gameId.toString() });
  await expect(game.state === 'Pending', `state=Pending (got ${game.state})`);
  await expect(game.whitePlayer.toLowerCase() === opp.address.toLowerCase(), 'opponent is white');
  await expect(game.blackPlayer.toLowerCase() === bot.address.toLowerCase(), 'bot is black');
  await expect(game.currentMove.toLowerCase() === bot.address.toLowerCase(), 'bot must accept (currentMove = bot)');

  // 7. Bot accepts via MCP
  console.log('\n[7] bot accepts challenge via MCP');
  const accept = await callTool('accept_challenge', { gameId: gameId.toString() });
  await expect(accept.status === 'success', `accept tx success (got ${accept.status})`);

  // 8. State should now be Started; currentMove = opp (white moves first)
  const game2 = await callTool('get_game', { gameId: gameId.toString() });
  await expect(game2.state === 'Started', `state=Started (got ${game2.state})`);
  await expect(game2.currentMove.toLowerCase() === opp.address.toLowerCase(), 'currentMove = opp after accept');

  // 9. Opponent plays e2e4 directly via viem
  console.log('\n[9] opponent plays e2e4 (direct viem)');
  const engine = await engineFor(gameId);
  const oppMoveHash = await engine.write.move([gameId, 'e2e4']);
  await publicClient.waitForTransactionReceipt({ hash: oppMoveHash });
  console.log('  ✓ opp move applied');

  // 10. Verify get_fen reflects the move
  console.log('\n[10] get_fen reflects e2e4');
  const fenAfter = await callTool('get_fen', { gameId: gameId.toString() });
  await expect(fenAfter.fen.includes('rnbqkbnr/pppppppp/8/8/4P3'), `fen shows e4 (${fenAfter.fen})`);

  // 11. Bot pulls legal moves and picks e7e5 via MCP
  console.log('\n[11] bot computes legal_moves');
  const legal = await callTool('legal_moves', { gameId: gameId.toString() });
  await expect(legal.legalMoves.some((m) => m.uci === 'e7e5'), 'e7e5 is in bot legal moves');

  console.log('\n[12] bot plays e7e5 via MCP');
  const botMove = await callTool('move', { gameId: gameId.toString(), uci: 'e7e5' });
  await expect(botMove.status === 'success', `bot move success (got ${botMove.status})`);

  // 13. render_board (text, not JSON)
  console.log('\n[13] render_board returns ASCII');
  const board = await callTool('render_board', { gameId: gameId.toString() });
  await expect(typeof board === 'string' && board.includes('+'), 'board includes ASCII grid chars');

  // 14. Bot resigns via MCP
  console.log('\n[14] bot resigns via MCP');
  const resignResult = await callTool('resign', { gameId: gameId.toString() });
  await expect(resignResult.status === 'success', `resign tx success (got ${resignResult.status})`);

  const game3 = await callTool('get_game', { gameId: gameId.toString() });
  await expect(game3.state === 'Finished', `state=Finished after resign (got ${game3.state})`);
  await expect(game3.outcome === 'WhiteWon', `outcome=WhiteWon (got ${game3.outcome})`);

  // 15. List history shows the game
  console.log('\n[15] bot history includes the game');
  const history = await callTool('list_history');
  const hist = history.history.map(BigInt);
  await expect(hist.includes(gameId), `gameId ${gameId} appears in bot's history`);

  // 16. validate_uci
  console.log('\n[16] validate_uci sanity');
  const goodUci = await callTool('validate_uci', { uci: 'e2e4' });
  await expect(goodUci.valid === true, 'e2e4 valid');
  const badUci = await callTool('validate_uci', { uci: 'z9z9' });
  await expect(badUci.valid === false, 'z9z9 invalid');

  console.log('\nALL CHECKS PASSED ✅');
  process.exit(0);
} catch (err) {
  console.error('\nVERIFICATION FAILED:', err.message);
  process.exit(1);
} finally {
  mcp.kill();
}
