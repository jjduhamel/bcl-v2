---
name: eth-ops
description: Ethereum key & wallet operations with Foundry cast — generate keypairs (one named keystore per agent via $AGENT_CAST_KEY / $AGENT_CAST_PASS), derive addresses, sign raw digests/messages/EIP-712, sign EIP-7702 authorizations, and sign ERC-4337 UserOp hashes for the BCL gasless-agent flow. Use it to onboard (a.k.a. enroll / register) an agent and sign its gasless moves.
version: 0.1.0
author: John Duhamel
license: MIT
metadata:
  hermes:
    tags: [Crypto, Ethereum, Keys, Signing]
---

# Ethereum Ops (cast)

Key, wallet, and signing primitives for an Ethereum agent, built on Foundry's `cast` (a single static
binary — no Node/Python deps). Mint an identity, derive its address, and produce every signature the BCL
MCP server needs to onboard (a.k.a. enroll / register) an agent and play chess gaslessly.

**Multiple agents, one keystore.** All keys live in the shared `~/.foundry/keystores`, each under its own
unique name. The bot reads its keystore **name** from `AGENT_CAST_KEY` and the keystore **password** from
`AGENT_CAST_PASS`, so every keystore command pairs `--account "$AGENT_CAST_KEY"` with
`--password "$AGENT_CAST_PASS"` and runs non-interactively. Each agent runs with its own values
(they share the keystore directory); `cast wallet list` shows them all.

## When to Use

- You need a **new keypair / identity** for an agent (a fresh seat).
- You hold a private key and need its **address**.
- The BCL MCP server returned `needsSignature` with a `digest` (from `delegate_agent`) or a `userOpHash`
  (from `move`/`resign`/…) and you must **sign that hash** to finish the round.
- You need a standalone **EIP-7702 authorization**, an EIP-712 / message signature, or to verify one.

## Prerequisite

`cast` (Foundry) is needed to run.

- The user may specify the precise location of `cast` with the BCL_CAST_PATH environment variable
- The default install location for `cast` is `/home/$USER/.foundry/bin/cast`.  
- `cast` might be installed on somewhere on the users `$PATH`.  This is a common location package managers use.

If you can't find cast at any of these locations, inform the user and pause.

Do not attempt to install cast.

Do not attempt to use python, javascript, or any alternative signing method when interacting with BCL.

`AGENT_CAST_KEY` (keystore name) and `AGENT_CAST_PASS` (keystore password) must both be set so signing is
non-interactive. **If either is unset, stop and alert the user — do not sign, guess, or proceed.** Guard
them before any keystore command:

```
: "${AGENT_CAST_KEY:?AGENT_CAST_KEY is not set — set it to this agent's cast keystore name}"
: "${AGENT_CAST_PASS:?AGENT_CAST_PASS is not set — set it to the keystore password}"
```

*Always* sign from the keystore.  Pass `--account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` to 
all cast calls — never inline `--private-key`.

## Quick Reference

| Task | Command |
|---|---|
| New keypair → this agent's keystore | `CAST_PASSWORD="$AGENT_CAST_PASS" cast wallet new ~/.foundry/keystores "$AGENT_CAST_KEY"` |
| Import an existing key → keystore | `cast wallet import "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS" --private-key <KEY>` |
| List all agents' keystores | `cast wallet list` |
| This agent's address | `cast wallet address --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` |
| Derive from mnemonic | `cast wallet private-key --mnemonic "<PHRASE>" --mnemonic-index <i>` |
| **Sign a precomputed 32-byte hash** | `cast wallet sign --no-hash <HASH> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` |
| Sign a plain message (EIP-191) | `cast wallet sign "<MESSAGE>" --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` |
| Sign EIP-712 typed data | `cast wallet sign --data <JSON-or-file> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` |
| EIP-7702 authorization (standalone) | `cast wallet sign-auth <IMPL> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS" --nonce <n> --chain <id>` |
| Verify a message signature | `cast wallet verify --address <ADDR> "<MESSAGE>" <SIG>` |

## Procedure

### Generate an identity

Mint a key into your named, encrypted keystore (non-interactive — password from `$AGENT_CAST_PASS`):
```
cast wallet new ~/.foundry/keystores "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"
```
Note the printed **Address** — that's this agent's seat. `cast wallet list` enumerates every agent. A
fresh key holds 0 ETH and isn't registered/delegated yet — that's the next two steps.

### Fetch your identity

Your **address** — the seat you act as — comes from your keystore. Fetch it at the start of a session,
since the MCP tools need it:
```
cast wallet address --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"
```
Use that address as **`sender`** when signing gasless ops, and as **`player`** when querying your own
state (`list_challenges`, `list_games`, `list_history`). For your on-chain standing — owner, registered,
delegated — call the MCP tool `agent_status` with `{ "agent": "<that address>" }`.

### Onboard a BCL agent (delegate_agent — two rounds)

Onboarding — also called **enrolling** or **registering** an agent — is two on-chain steps: the *owner*
first registers the agent (`registerAgent`, from the owner's wallet — not this skill, not gasless), then
the *agent itself* delegates to the AgentAccount via the round-trip below. `agent_status` should end at
`registered: true, delegated: true`.

1. Call the MCP tool `delegate_agent` with `{ "agent": "<AGENT_ADDR>" }` → `{ needsSignature, digest, nonce }`.
2. Sign the **digest** raw:
   ```
   cast wallet sign --no-hash <digest> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"
   ```
3. Call `delegate_agent` again with `{ agent, signature, nonce }`. The server submits the type-4 setCode
   tx and the agent is delegated.

### Play a gasless move (move — two rounds)

1. `move` with `{ gameId, uci, sender: "<AGENT_ADDR>" }` → `{ needsSignature, userOpHash, userOp }`.
2. Sign the **userOpHash** raw:
   ```
   cast wallet sign --no-hash <userOpHash> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"
   ```
3. `move` again with `{ gameId, uci, signature, userOp }`. The relayer submits `handleOps`; the Lobby
   paymaster pays. Same pattern for `resign` / `offer_draw` / `respond_draw` / `claim_victory` /
   `raise_dispute`.

### Standalone EIP-7702 delegation (outside the MCP server)

Only if you broadcast the type-4 tx yourself (e.g. `cast send --auth`), not via the MCP server:
```
cast wallet sign-auth <IMPL> --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS" --nonce <n> --chain <chainId>
```

## Pitfalls

- **`AGENT_CAST_KEY` + `AGENT_CAST_PASS` are this agent's identity.** Each agent runs with its own pair. If
  either is **unset**, alert the user and abort — never sign without them; if the name is wrong, you sign as
  the wrong agent. Confirm with `cast wallet address --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"`.
- **The private key IS the identity.** Never log, commit, or paste the raw key; sign from the keystore, not
  inline `--private-key`. Back up each keystore file + its password — losing them loses that agent and any
  earnings tied to it.
- **`--no-hash` is mandatory for MCP digests / userOpHashes.** They are already 32-byte hashes, and the BCL
  account recovers from the *raw* hash. Without `--no-hash`, `cast` prefixes the EIP-191 header and
  re-hashes, producing a signature that fails on-chain recovery.
- **7702 nonce semantics.** When a relayer (≠ the authority) broadcasts, the nonce is the authority's
  *current* account nonce — what the MCP server returns, so echo it back. If the signer broadcasts its
  own authorization, the nonce is current + 1 (see `cast wallet sign-auth --help`).
- **chain id must match the target chain** for a 7702 authorization (BCL local anvil = `31337`).

## Verification

- `cast wallet list` shows the agent's name; `cast wallet address --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS"` returns its address.
- Round-trip: `S=$(cast wallet sign "hi" --account "$AGENT_CAST_KEY" --password "$AGENT_CAST_PASS")` then
  `cast wallet verify --address <ADDR> "hi" "$S"` prints `Validation succeeded`.
- After `delegate_agent`, `agent_status` shows `delegated: true` with `impl` = the AgentAccount; after a
  `move`, `get_moves` reflects the move and the agent's ETH balance stays 0.


