# bcl-mcp

A Model Context Protocol server that exposes the [BCL](../README.md) chess wagering contracts to AI assistants. The bot connects to a deployed `Lobby` + `ChessEngine` pair and can play full games against human (or other bot) opponents — accepting challenges, computing legal moves, submitting moves, resigning, claiming victory on timeout, disputing games, and withdrawing winnings.

**Status:** localhost-only for now. The server rejects any chain other than anvil (`chainId 31337`) at startup. Session-key delegation (running against testnet/mainnet with bounded permissions) is on the roadmap.

## Tool surface (27 tools)

| Module | Tools |
|---|---|
| Player actions | `challenge`, `accept_challenge`, `modify_challenge`, `decline_challenge`, `move`, `resign`, `offer_draw`, `respond_draw`, `claim_victory`, `raise_dispute`, `withdraw` |
| Lobby reads | `list_challenges`, `list_games`, `list_history`, `player_stats`, `player_finance`, `check_deposit`, `platform_fee`, `lounge_stats` |
| Game reads | `get_game`, `get_moves`, `get_fen`, `render_board`, `time_remaining`, `game_engine_addr` |
| Chess utilities | `legal_moves`, `validate_uci` |

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

| Var | Required | Default | Purpose |
|---|---|---|---|
| `LOBBY_ADDRESS` | yes | — | Deployed Lobby proxy address (e.g. `0x171889…`) |
| `PRIVATE_KEY` | yes | — | The bot's signing key (0x-prefixed hex). For anvil dev, derive from `../.mnemonic`. |
| `RPC_URL` | no | `http://127.0.0.1:8545` | JSON-RPC endpoint. Defaults to explicit IPv4 — `localhost` resolves to `::1` on many Linux setups while anvil only binds `127.0.0.1`, and Node's fetch does not fall back. |

Extracting both from the repo (run from repo root):

```bash
# LOBBY_ADDRESS — the ERC1967Proxy from the latest DeployLobby broadcast
jq -r '[.transactions[] | select(.contractName == "ERC1967Proxy")][0].contractAddress' \
  broadcast/DeployLobby.s.sol/31337/run-latest.json

# PRIVATE_KEY — derived from .mnemonic via Foundry's cast
cast wallet private-key --mnemonic "$(cat .mnemonic)" --mnemonic-index 0
```

In development mode (`yarn dev`) both are derived automatically; see below.

## Run

```bash
LOBBY_ADDRESS=0x... PRIVATE_KEY=0x... node dist/index.js
```

The server reads/writes JSON-RPC frames on stdin/stdout (the MCP stdio transport). It logs a one-line connection diagnostic to stderr on startup; stdout is reserved for protocol traffic.

## Development mode

For local iteration on tools and helpers, use `yarn dev` — it skips the `tsc` build, runs TypeScript directly via `tsx`, and **auto-resolves the dev env vars from local files** so you don't have to plumb them by hand:

```bash
yarn dev
```

The dev wrapper (`scripts/dev.mjs`) reads:

- `LOBBY_ADDRESS` from the latest `../broadcast/DeployLobby.s.sol/31337/run-latest.json` (the `ERC1967Proxy` contractAddress)
- `PRIVATE_KEY` from `../.mnemonic` via viem's HD derivation at `MNEMONIC_INDEX` (default 0)

On startup it prints a one-line banner naming the resolved bot address and lobby. To run as a different anvil account:

```bash
MNEMONIC_INDEX=1 yarn dev
```

Any explicitly set `LOBBY_ADDRESS`, `PRIVATE_KEY`, or `RPC_URL` env var still takes priority — the wrapper only fills in the gaps.

The `scripts/verify.mjs` end-to-end driver is useful for smoke tests after a tool change: it spawns the built server, drives a full game against an anvil opponent, and exits non-zero on the first failed assertion.

```bash
yarn build && node scripts/verify.mjs
```

To point an MCP client at the dev wrapper (so source edits land without a recompile, and env vars come from local files), have it invoke `yarn --cwd … dev` instead of `node dist/index.js`:

```jsonc
{
  "command": "yarn",
  "args": ["--cwd", "/home/jjd/Sources/bcl/bcl-v2/mcp", "dev"]
}
```

No `env` block needed unless you want to override `MNEMONIC_INDEX` or pin to a specific lobby/key.

## Claude Code integration

Register the dev wrapper as a local-scoped server — no env block needed, since the wrapper derives `LOBBY_ADDRESS` and `PRIVATE_KEY` from local files at launch:

```bash
claude mcp add bcl \
  /home/jjd/.local/share/mise/installs/node/22.22.3/bin/node \
  /home/jjd/Sources/bcl/bcl-v2/mcp/scripts/dev.mjs
```

(The explicit Node 22 path side-steps an outer-shell PATH that resolves to Node 18.)

Verify with `claude mcp list` — `bcl` should report `✓ Connected`. The 27 tools then appear under the `bcl` namespace; check with `/mcp` inside a Claude Code session.

For a pinned, build-based install (env vars set explicitly, no auto-derivation), use `dist/index.js` instead:

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

## Architecture notes

- **ABIs.** Loaded at runtime from `../out/Lobby.sol/Lobby.json` and `../out/ChessEngine.sol/ChessEngine.json` via `createRequire` — same Forge artifacts the frontend consumes. No codegen.
- **Per-game engine resolution.** Every engine-targeting tool resolves the engine address via `lobby.chessEngine(gameId)` per call. Older games stay pinned to their original engine after upgrades; never cache `currentEngine()`.
- **Chess state.** chess.js 1.4 replays the on-chain UCI log to produce FEN, ASCII board, and legal moves. The replay mirrors `client/composables/useChessEngine.js`, including the pseudo-legal fallback for castle-through-check and king-in-check moves (the contract permits both; chess.js's public `.move()` doesn't).
- **Signing.** A single PRIVATE_KEY is loaded at startup and used for all writes. The chain-id guard in `src/chain.ts` rejects any chain other than anvil; see the `// TODO: session-key delegation` marker for the planned path off localhost.
- **Errors.** Contract reverts propagate verbatim — no role gating on the tool surface. Calls that need privileges the bot doesn't have will fail with the contract's own revert reason.

## Layout

```
mcp/
├── src/
│   ├── index.ts              stdio entrypoint, registers all tool modules
│   ├── chain.ts              viem clients, env validation, chain-id guard
│   ├── chess.ts              chess.js replay + legal moves + UCI validator
│   ├── util.ts               JSON helpers and a tsc-friendly tool() wrapper
│   ├── contracts/
│   │   ├── lobby.ts
│   │   └── chessEngine.ts    per-game engine resolver
│   └── tools/
│       ├── playerActions.ts
│       ├── lobbyReads.ts
│       ├── gameReads.ts
│       └── chessUtils.ts
└── scripts/
    ├── dev.mjs               yarn dev wrapper — derives env from .mnemonic + broadcast
    └── verify.mjs            end-to-end driver (spawns server, plays a game)
```
