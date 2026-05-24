# bcl-mcp

A Model Context Protocol server that exposes the [BCL](../README.md) chess wagering contracts to AI assistants. The bot connects to a deployed `Lobby` + `ChessEngine` pair and can play full games against human (or other bot) opponents — accepting challenges, computing legal moves, submitting moves, resigning, claiming victory on timeout, disputing games, and withdrawing winnings.

**Status:** localhost-only for now. The server rejects any chain other than anvil (`chainId 31337`) at startup. Session-key delegation (running against testnet/mainnet with bounded permissions) is on the roadmap — see [Session-key delegation (planned)](#session-key-delegation-planned).

## Tool surface (27 tools)

| Module | Tools |
|---|---|
| Lobby (13) | `list_challenges`, `list_games`, `list_history`, `player_stats`, `player_finance`, `check_deposit`, `platform_fee`, `lounge_stats`, `challenge`, `accept_challenge`, `modify_challenge`, `decline_challenge`, `withdraw` |
| Game (14) | `get_game`, `get_moves`, `get_fen`, `render_board`, `time_remaining`, `game_engine_addr`, `legal_moves`, `validate_uci`, `move`, `resign`, `offer_draw`, `respond_draw`, `claim_victory`, `raise_dispute` |

## Prerequisites

- Node 22 LTS (pinned in `../.mise.toml`)
- yarn (project convention — never `npm install`)
- A running anvil instance (`yarn devchain` in the repo root) seeded from `../.mnemonic`
- Deployed contracts (`yarn deploy:lobby` then `forge script DeployEngine` from the repo root)
- The deployed Lobby proxy address

## Build

```bash
cd mcp
yarn install
yarn build       # tsc → dist/
```

The TypeScript build requires `NODE_OPTIONS=--max-old-space-size=8192` on machines with less than 8 GB free heap — viem's ABI-derived types push tsc past its default budget. If you hit OOM during build, prepend the env var:

```bash
NODE_OPTIONS=--max-old-space-size=8192 yarn build
```

## Environment variables

All config comes from `mcp/.env` (or the process environment for production deployments). Copy the template to start:

```bash
cp mcp/.env.example mcp/.env
# edit mcp/.env
```

| Var | Required | Default | Purpose |
|---|---|---|---|
| `LOBBY_ADDRESS` | yes | — | Deployed Lobby proxy address (e.g. `0x171889…`) |
| `PRIVATE_KEY` | dev only | — | The bot's signing key (0x-prefixed hex). **Must be unset in prod** — startup aborts otherwise. |
| `NODE_ENV` | no | unset | Set to `production` to disable server-side signing (see [Production mode](#production-mode)). |
| `RPC_URL` | no | `http://127.0.0.1:8545` | JSON-RPC endpoint. Defaults to explicit IPv4 — `localhost` resolves to `::1` on many Linux setups while anvil only binds `127.0.0.1`, and Node's fetch does not fall back. |

`mcp/.env` is gitignored (matched by the repo-root `*.env` rule).

To seed the dev values from local artifacts (run from repo root):

```bash
# LOBBY_ADDRESS — the ERC1967Proxy from the latest DeployLobby broadcast
jq -r '[.transactions[] | select(.contractName == "ERC1967Proxy")][0].contractAddress' \
  broadcast/DeployLobby.s.sol/31337/run-latest.json

# PRIVATE_KEY — derived from .mnemonic via Foundry's cast
cast wallet private-key --mnemonic "$(cat .mnemonic)" --mnemonic-index 0
```

## Run

```bash
LOBBY_ADDRESS=0x... PRIVATE_KEY=0x... node dist/index.js
```

The server reads/writes JSON-RPC frames on stdin/stdout (the MCP stdio transport). It logs a one-line connection diagnostic to stderr on startup; stdout is reserved for protocol traffic.

## Development mode

For local iteration on tools and helpers, use `yarn dev` — it skips the `tsc` build and runs TypeScript directly via `tsx`:

```bash
yarn dev
```

The dev wrapper (`scripts/dev.mjs`) loads `mcp/.env` via Node 22's built-in `process.loadEnvFile`, validates that `PRIVATE_KEY` and `LOBBY_ADDRESS` are set, prints a one-line banner with the resolved bot address and lobby, then execs `tsx src/index.ts`. Values already in the process environment take precedence over the file.

If `mcp/.env` is missing or required vars aren't set, the wrapper bails with a pointer to `mcp/.env.example`.

The `scripts/verify.mjs` end-to-end driver is useful for smoke tests after a tool change: it spawns the built server, drives a full game against an anvil opponent, and exits non-zero on the first failed assertion.

```bash
yarn build && node scripts/verify.mjs
```

To point an MCP client at the dev wrapper (so source edits land without a recompile), have it invoke `yarn --cwd … dev` instead of `node dist/index.js`:

```jsonc
{
  "command": "yarn",
  "args": ["--cwd", "/home/jjd/Sources/bcl/bcl-v2/mcp", "dev"]
}
```

No `env` block needed — the wrapper sources everything from `mcp/.env`.

## Production mode

Set `NODE_ENV=production` to disable server-side signing. In prod:

- **No `PRIVATE_KEY`.** Startup aborts if it's set — defense in depth so a stray env var can't custody keys on a hosted server.
- **No server-level identity.** Prod is multi-tenant: many AI agents share one server, each with their own EOA. There is no "the bot" — every call carries its own actor.
  - Read tools with an optional `player` arg (e.g. `list_games`, `player_stats`) now require it — there's no bot to default to.
  - Write tools require `from` in round 1 (see below).
- **Writes are two rounds** through the same tool. The first call returns a digest the AI signs externally; the second call attaches the signature and broadcasts.

### Round 1 — server returns digest

```jsonc
// client → server
{ "name": "move", "arguments": { "gameId": 2, "uci": "e7e5", "from": "0xAgent…" } }

// server → client
{
  "needsSignature": true,
  "digest": "0xa12b…",         // keccak256 of the EIP-1559 envelope
  "unsignedTx": "0x02f8…"      // serialized envelope, echo back in round 2
}
```

### Round 2 — caller signs and resubmits

The AI signs `digest` with whatever external signer it has (browser wallet bridge, hardware-wallet sidecar, another MCP — outside this server's scope) and calls the same tool again with `signature` + `unsignedTx`:

```jsonc
// client → server
{ "name": "move", "arguments": { "gameId": 2, "uci": "e7e5", "signature": "0x…", "unsignedTx": "0x02f8…" } }

// server → client
{ "txHash": "0x…", "blockNumber": "31", "status": "success", "gasUsed": "131203", "signer": "0xAgent…" }
```

`gameId` / `uci` in round 2 are ignored — `unsignedTx` is the canonical truth. The signer recovered from `signature` is returned for audit and visibility.

### Manual round-2 signature with `cast`

For interactive testing or as a reference signer:

```bash
# digest comes from the round-1 response
cast wallet sign --no-hash 0xa12b… --private-key 0x…
```

`--no-hash` is important: the digest is already a 32-byte hash, not a message to be wrapped with the Ethereum signed-message prefix.

### Out of scope

How the AI obtains a signature is intentionally not this server's problem. Likely paths in a real deployment: a wallet-bridge MCP on the AI's side, an EIP-7702 smart account, or the [planned session-key delegation](#session-key-delegation-planned) layer (which makes the AI's signing key a scoped delegate of the principal).

## Claude Code integration

Register the dev wrapper as a local-scoped server. No `env` block is needed since the wrapper loads `LOBBY_ADDRESS` and `PRIVATE_KEY` from `mcp/.env` at launch:

```bash
claude mcp add bcl \
  /home/jjd/.local/share/mise/installs/node/22.22.3/bin/node \
  /home/jjd/Sources/bcl/bcl-v2/mcp/scripts/dev.mjs
```

(The explicit Node 22 path side-steps an outer-shell PATH that resolves to Node 18.)

Verify with `claude mcp list` — `bcl` should report `✓ Connected`. The 27 tools then appear under the `bcl` namespace; check with `/mcp` inside a Claude Code session.

For a pinned, build-based install (env vars passed by the MCP client rather than read from `mcp/.env`), use `dist/index.js` instead:

```bash
claude mcp add bcl node /home/jjd/Sources/bcl/bcl-v2/mcp/dist/index.js \
  -e LOBBY_ADDRESS=0x... \
  -e PRIVATE_KEY=0x... \
  -e RPC_URL=http://127.0.0.1:8545
```

Or equivalently in `.mcp.json` (committed) / `~/.claude.json` (private):

```jsonc
{
  "mcpServers": {
    "bcl": {
      "command": "node",
      "args": ["/home/jjd/Sources/bcl/bcl-v2/mcp/dist/index.js"],
      "env": {
        "LOBBY_ADDRESS": "0x1718896de70275f2967b288c5ab106a473a54782",
        "PRIVATE_KEY": "0x...",
        "RPC_URL": "http://127.0.0.1:8545"
      }
    }
  }
}
```

## Session-key delegation (planned)

> **Not yet implemented.** This section sketches the intended workflow for running the bot in *proxy mode* — signing on behalf of a human player rather than as a bot-persona EOA. The required contract pieces (`Lobby.setSessionKey`, a permissions bitmap, and a per-action modifier change to accept an explicit `principal`) don't exist yet; the chain-id guard in `src/chain.ts` will only be lifted once they do.

Today, `PRIVATE_KEY` in `mcp/.env` is the bot's own EOA — it *is* the principal. Proxy mode introduces three roles:

| Role | Holds | Description |
|---|---|---|
| Principal | EOA private key + funds | The human player. Wallet holds the wager balance, stats accrue here. Never shares its key with the agent. |
| Signer | Ephemeral EOA private key | A throwaway EOA the agent signs with. Only authority is what the principal grants on-chain. |
| Agent | Signer key + principal address | This bcl-mcp instance. Signs txs from the signer key; never sees the principal's key. |

### Workflow

1. **Generate a fresh signer keypair.** Any 32-byte secret; foundry's `cast` is convenient:

   ```bash
   cast wallet new
   # Address:     0xa11ce…
   # Private key: 0xdeadbeef…
   ```

   Treat the private key like any production secret: never commit, never log.

2. **Hand the signer's address (only) to the principal**, along with the desired scope:
   - **Permissions bitmap** — which methods the signer can call. Sensible default: low-risk game ops on (`move`, `offer_draw`, `respond_draw`, `resign`, `claim_victory`, `raise_dispute`); wager ops off (`challenge`, `accept_challenge`, …); `withdraw` off.
   - **Expiry** — UNIX timestamp after which the contract rejects signer-routed calls.
   - **Wager cap** — per-call max (0 = unlimited; only meaningful when `challenge`-class perms are on).

3. **Principal submits the delegation from their own wallet** — one tx, signed by the principal's EOA:

   ```solidity
   lobby.setSessionKey(SessionKey({
       signer:      0xa11ce…,
       expiresAt:   1735689600,                                      // e.g. 2025-01-01
       wagerCap:    0.1 ether,
       permissions: PERM_MOVE | PERM_RESIGN | PERM_OFFER_DRAW | PERM_RESPOND_DRAW
   }));
   ```

   The principal can revoke at any time with `revokeSessionKey()`; the slot is per-principal so the next `setSessionKey` overwrites the previous signer.

4. **Fund the signer for gas.** The signer EOA pays its own gas — it's a regular account.
   - Self-host: principal sends a small ETH budget (e.g. 0.01 ETH) to the signer address in a follow-up tx; agent surfaces a "running low" error when the budget nears empty.
   - Hosted: agent operator runs a relayer wallet that tops up signers on demand and recovers cost via the platform fee.

5. **Insert the signer key into the agent.** Self-host reuses `mcp/.env` with one new var:

   ```dotenv
   PRIVATE_KEY=0xdeadbeef…       # signer (NOT the principal's key)
   PRINCIPAL_ADDRESS=0xPrincipal  # the EOA the signer acts for
   LOBBY_ADDRESS=0x…
   ```

   Hosted mode loads signers from a per-principal keystore (KMS-backed envelope encryption). There is no plaintext multi-user fallback — co-mingled plaintext keys are explicitly out of scope.

6. **Agent routes writes through the signer.** Write tools (`move`, `resign`, …) gain an optional `as: address` parameter defaulting to the bound `PRINCIPAL_ADDRESS`. The contract validates `msg.sender == principal || authorized(principal, msg.sender, perm)` and reverts otherwise. Wagers, stats, and payouts continue to accrue to the principal.

### Revocation and rotation

- **Revoke:** principal sends `lobby.revokeSessionKey()`. The next agent write reverts; rebind with a fresh signer.
- **Rotate:** generate a new signer, principal calls `setSessionKey` again. The slot is overwritten — no extra revoke tx needed.
- **Expiry:** the contract enforces `expiresAt`. Agent does a pre-flight read of `__sessionKey[principal]` before each write so an expired key fails fast without burning gas.

### What the agent never holds

- The principal's EOA private key.
- ETH or tokens beyond the signer's own gas budget. Wagers stay in the principal's name; `withdraw` (when permitted) releases to the principal, not the signer.

### Open issues blocking implementation

- Contract: `SessionKey` struct, per-principal mapping, `setSessionKey` / `revokeSessionKey` / `authorized(...)`, and parametrizing the existing `isPlayer` / `isCurrentMove` modifiers to take an explicit `principal`.
- Contract: `withdraw` must release to `principal`, not `msg.sender`, when the call comes via a session key — otherwise a compromised signer drains earnings.
- Contract: `challenge` / `acceptChallenge` need a principal-deposit code path so ETH wagers come from a Lobby-held principal balance, not `msg.value` from the signer.
- Agent: keystore abstraction (`BotKeystore` / `LocalFileKeystore` / `KmsKeystore`), principal binding on the MCP session, ensure-gas-budget hook before each write.

## Architecture notes

- **ABIs.** Loaded at runtime from `../out/Lobby.sol/Lobby.json` and `../out/ChessEngine.sol/ChessEngine.json` via `createRequire` — same Forge artifacts the frontend consumes. No codegen.
- **Per-game engine resolution.** Every engine-targeting tool resolves the engine address via `lobby.chessEngine(gameId)` per call. Older games stay pinned to their original engine after upgrades; never cache `currentEngine()`.
- **Chess state.** chess.js 1.4 replays the on-chain UCI log to produce FEN, ASCII board, and legal moves. The replay mirrors `client/composables/useChessEngine.js`, including the pseudo-legal fallback for castle-through-check and king-in-check moves (the contract permits both; chess.js's public `.move()` doesn't).
- **Signing.** A single PRIVATE_KEY is loaded at startup and used for all writes. The chain-id guard in `src/chain.ts` rejects any chain other than anvil; see the `// TODO: session-key delegation` marker for the planned path off localhost.
- **Errors.** Contract reverts propagate verbatim — no role gating on the tool surface. Calls that need privileges the bot doesn't have will fail with the contract's own revert reason.

## Layout

```
mcp/
├── .env.example             template for mcp/.env (PRIVATE_KEY, LOBBY_ADDRESS, RPC_URL)
├── src/
│   ├── index.ts             stdio entrypoint, registers lobby + game tool modules
│   ├── chain.ts             viem clients, env validation, chain-id guard, tx submit helper
│   ├── chess.ts             chess.js replay + legal moves + UCI validator
│   ├── util.ts              JSON helpers and a tsc-friendly tool() wrapper
│   ├── contracts/
│   │   ├── lobby.ts
│   │   └── chessEngine.ts   per-game engine resolver
│   └── tools/
│       ├── lobby.ts         lobby-scoped tools (lists, stats, challenges, withdraw)
│       └── game.ts          game-scoped tools (state, moves, chess utils, in-game actions)
└── scripts/
    ├── dev.mjs              yarn dev wrapper — loads mcp/.env and execs tsx
    └── verify.mjs           end-to-end driver (spawns server, plays a game)
```
