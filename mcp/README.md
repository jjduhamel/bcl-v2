# bcl-mcp

A Model Context Protocol server that lets an AI agent play [BCL](../README.md) chess — reading game state, computing legal moves, and submitting moves, resignations, draw offers, timeout claims, and disputes. Agents play **gaslessly**: they hold no ETH, and the server sponsors every move via the Lobby's ERC-4337 paymaster (EIP-7702).

**Status:** localhost-only for now — the server only talks to a local anvil (`chainId 31337`).

## What the agent can do

| Module | Tools |
|---|---|
| Lobby reads (8) | `list_challenges`, `list_games`, `list_history`, `player_stats`, `player_finance`, `check_deposit`, `platform_fee`, `lounge_stats` |
| Lobby writes (5) | `challenge`, `accept_challenge`, `modify_challenge`, `decline_challenge`, `withdraw` |
| Game (14) | `get_game`, `get_moves`, `get_fen`, `render_board`, `time_remaining`, `game_engine_addr`, `legal_moves`, `validate_uci`, `move`, `resign`, `offer_draw`, `respond_draw`, `claim_victory`, `raise_dispute` |
| Agent (2) | `delegate_agent`, `agent_status` |

Before an agent can play, it must be **registered** in the Lobby (done by its owner) and **delegated** via `delegate_agent`. The 5 Lobby write tools (challenging, accepting, withdrawing) are owner-side actions done from a wallet or the web app — they are not gasless, so calling them here returns an error.

## Prerequisites

- Node 22 (pinned in `.mise.toml`) and yarn (never `npm install`)
- A local anvil with the Prague hardfork and the BCL contracts deployed. From the repo root:

  ```bash
  yarn devchain --hardfork prague      # in one terminal
  yarn deploy:local                    # deploy contracts + EntryPoint
  ```

## Configuration

Copy the template and fill it in:

```bash
cp mcp/.env.example mcp/.env
```

| Var | Required | Default | Purpose |
|---|---|---|---|
| `LOBBY_ADDRESS` | yes | — | Deployed Lobby proxy address |
| `PRIVATE_KEY` | yes | — | The relayer / gas-sponsor key. The server uses it only to pay gas — it never plays. |
| `AGENT_ACCOUNT` | yes | — | The agent-account implementation address (the 7702 delegate target) |
| `ENTRY_POINT` | no | canonical v0.8 | EntryPoint address |
| `RPC_URL` | no | `http://127.0.0.1:8545` | JSON-RPC endpoint |

The deployed addresses are printed by `yarn deploy:local` and saved to the repo-root `.env`.

## Development server

Runs the server straight from TypeScript (no build step), reloading config from `mcp/.env`:

```bash
cd mcp
yarn install
yarn dev
```

## Production bundle

Compile to `dist/` and run the built server:

```bash
cd mcp
yarn install
yarn build       # tsc → dist/
yarn start       # node dist/index.js
```

If the build runs out of memory (viem's types are heavy), give Node more heap:

```bash
NODE_OPTIONS=--max-old-space-size=8192 yarn build
```

## Use with Claude Code

Register the dev server as a local MCP server (it reads `mcp/.env`, so no `env` block is needed):

```bash
claude mcp add bcl \
  /home/jjd/.local/share/mise/installs/node/22.22.3/bin/node \
  /home/jjd/Sources/bcl/bcl-v2/mcp/scripts/dev.mjs
```

(The explicit Node 22 path avoids a shell that resolves to an older Node.) For the built bundle instead, point at `dist/index.js` and pass `-e LOBBY_ADDRESS=… -e AGENT_ACCOUNT=… -e PRIVATE_KEY=… -e RPC_URL=…`. Verify with `claude mcp list` (`bcl` should show `✓ Connected`); the tools appear under the `bcl` namespace.
