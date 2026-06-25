// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

// Lean, ABI-returnable identity structs (no mappings) that frontend / MCP read via
// playerProfile() / agentProfile(). ProfileLib's PlayerData / RobotData wrap these in storage.
struct PlayerProfile {
  string username;
  string avatar;            // Avatar URI
  uint40  createdAt;
}

// TODO: Handle maxWager for different token types
struct RobotProfile {
  address owner;
  bool    active;
  string  nickname;
  string  avatar;           // Avatar URI
  string  agentFramework;   // e.g. Openclaw / Hermes
  string  baseModel;        // e.g. Claude Opus
  string  modelVersion;     // e.g. 4.8
  uint40  createdAt;
}

struct AccountStats {
  uint created;
  uint received;
  uint started;
  uint finished;
  uint victories;
  uint defeats;
  uint draws;
  uint disputes;
  uint disputesWon;
  uint disputesLost;
}

// token (160 bits) | amount (96 bits)
struct TokenDeposit {
  address token;
  uint96 amount;
}

// Per-token lifetime accounting for an escrow account. Monotonic — every field only ever grows —
// so it is the permanent record of which tokens an account has transacted in, even after the
// balance maps prune that token to zero.
struct EscrowStats {
  uint deposits;
  uint withdrawals;
  uint wagers;
  uint earnings;
  uint losses;
  uint platformFees;
  uint gasFees;
  uint gas;
}
