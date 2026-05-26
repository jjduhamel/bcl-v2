import { z } from 'zod';
import { zeroAddress, type Address } from 'viem';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { lobby, lobbyAbi } from '../contracts/lobby.js';
import { resolvePlayer } from '../chain.js';
import { agentOpFields, submitUserOp } from '../userop.js';
import { textResult, tool } from '../util.js';

const addressSchema = z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x-prefixed 40-hex address');
const gameIdSchema = z.union([z.number().int().nonnegative(), z.string().regex(/^\d+$/)])
  .transform((v) => BigInt(v));
const bigUintSchema = z.union([
  z.number().int().nonnegative(),
  z.string().regex(/^\d+$/),
]).transform((v) => BigInt(v));

export function registerLobbyTools(server: McpServer) {
  tool(server,
    'list_challenges',
    {
      title: 'List pending challenges',
      description: 'Pending challenge IDs for a player. Includes both sent and received challenges.',
      inputSchema: { player: addressSchema.optional() },
    },
    async ({ player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const ids = (await lobby.read.challenges([addr])) as bigint[];
      return textResult({ player: addr, challenges: ids });
    },
  );

  tool(server,
    'list_games',
    {
      title: 'List active games',
      description: 'Game IDs the player is currently in (state: Started, Draw-offered, or Review).',
      inputSchema: { player: addressSchema.optional() },
    },
    async ({ player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const ids = (await lobby.read.games([addr])) as bigint[];
      return textResult({ player: addr, games: ids });
    },
  );

  tool(server,
    'list_history',
    {
      title: 'List finished games',
      description: 'Game IDs the player has finished (state: Finished, including draws).',
      inputSchema: { player: addressSchema.optional() },
    },
    async ({ player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const ids = (await lobby.read.history([addr])) as bigint[];
      return textResult({ player: addr, history: ids });
    },
  );

  tool(server,
    'list_agents',
    {
      title: "List a player's agents",
      description: 'Agent EOAs a player owns (registered via registerAgent). Each can be delegated and play gaslessly on the owner\'s behalf.',
      inputSchema: { player: addressSchema.optional() },
    },
    async ({ player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const agents = (await lobby.read.agents([addr])) as Address[];
      return textResult({ player: addr, agents });
    },
  );

  tool(server,
    'player_stats',
    {
      title: 'Player game stats',
      description: 'Aggregate stats for a player: wins/losses/draws and counters.',
      inputSchema: { player: addressSchema.optional() },
    },
    async ({ player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const [
        totalWins,
        totalLosses,
        totalDraws,
        gamesStarted,
        gamesFinished,
        challengesSent,
        challengesReceived,
      ] = (await Promise.all([
        lobby.read.totalWins([addr]),
        lobby.read.totalLosses([addr]),
        lobby.read.totalDraws([addr]),
        lobby.read.gamesStarted([addr]),
        lobby.read.gamesFinished([addr]),
        lobby.read.challengesSent([addr]),
        lobby.read.challengesReceived([addr]),
      ])) as bigint[];
      return textResult({
        player: addr,
        totalWins,
        totalLosses,
        totalDraws,
        gamesStarted,
        gamesFinished,
        challengesSent,
        challengesReceived,
      });
    },
  );

  tool(server,
    'player_finance',
    {
      title: 'Player wager and earnings totals',
      description:
        'Lifetime wager totals plus current withdrawable balance for the given token (default ETH).',
      inputSchema: {
        player: addressSchema.optional(),
        token: addressSchema.optional(),
      },
    },
    async ({ player, token }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const tok = (token ?? zeroAddress) as Address;
      const [grossWagers, grossWinnings, grossLosses, earnings] = (await Promise.all([
        lobby.read.grossWagers([addr]),
        lobby.read.grossWinnings([addr]),
        lobby.read.grossLosses([addr]),
        lobby.read.checkPlayerEarnings([addr, tok]),
      ])) as bigint[];
      return textResult({
        player: addr,
        token: tok,
        grossWagers,
        grossWinnings,
        grossLosses,
        withdrawableEarnings: earnings,
      });
    },
  );

  tool(server,
    'check_deposit',
    {
      title: 'Inspect escrow deposit',
      description: 'Amount held in lobby escrow for a player on a given game (defaults to bot in dev mode).',
      inputSchema: {
        gameId: gameIdSchema,
        player: addressSchema.optional(),
      },
    },
    async ({ gameId, player }) => {
      const addr = resolvePlayer(player as Address | undefined);
      const amount = (await lobby.read.checkPlayerDeposit([gameId, addr])) as bigint;
      return textResult({ gameId, player: addr, amount });
    },
  );

  tool(server,
    'platform_fee',
    {
      title: 'Platform fee for a game',
      description: 'The fee (in wager-token units) the platform takes from each side at game start.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const fee = (await lobby.read.platformFee([gameId])) as bigint;
      return textResult({ gameId, platformFee: fee });
    },
  );

  tool(server,
    'lounge_stats',
    {
      title: 'Lounge-wide stats',
      description: 'Global counters: total wagers/winnings/losses and game counts.',
      inputSchema: {},
    },
    async () => {
      const [
        grossWagers,
        grossWinnings,
        grossLosses,
        netEarnings,
        totalChallenges,
        totalGames,
        totalFinishes,
      ] = await Promise.all([
        lobby.read.grossWagers([]) as Promise<bigint>,
        lobby.read.grossWinnings([]) as Promise<bigint>,
        lobby.read.grossLosses([]) as Promise<bigint>,
        lobby.read.netEarnings([]) as Promise<bigint>,
        lobby.read.totalChallenges([]) as Promise<bigint>,
        lobby.read.totalGames([]) as Promise<bigint>,
        lobby.read.totalFinishes([]) as Promise<bigint>,
      ]);
      return textResult({
        grossWagers,
        grossWinnings,
        grossLosses,
        netEarnings,
        totalChallenges,
        totalGames,
        totalFinishes,
      });
    },
  );

  tool(server,
    'challenge',
    {
      title: 'Open a new challenge',
      description:
        'Create a challenge against an opponent. NOTE: not available under the 7702-only path (the Lobby paymaster sponsors only engine moves) — returns an error. Open challenges from an owner wallet / the frontend.',
      inputSchema: {
        opponent: addressSchema,
        startAsWhite: z.boolean().default(true),
        timePerMove: bigUintSchema.describe('Seconds allowed per move'),
        wagerAmount: bigUintSchema.default(0).describe('Wager in wei (or token base units)'),
        wagerToken: addressSchema.optional(),
        ...agentOpFields,
      },
    },
    async ({ opponent, startAsWhite, timePerMove, wagerAmount, wagerToken, sender, signature, userOp }) => {
      const token = (wagerToken ?? zeroAddress) as Address;
      return submitUserOp(
        { sender, signature, userOp },
        {
          engine: lobby.address,
          abi: lobbyAbi,
          functionName: 'challenge',
          args: [opponent as Address, startAsWhite, timePerMove, wagerAmount, token],
        },
      );
    },
  );

  tool(server,
    'accept_challenge',
    {
      title: 'Accept a pending challenge',
      description:
        'Accept a pending challenge. NOTE: not available under the 7702-only path (the Lobby paymaster sponsors only engine moves) — returns an error. Accept from an owner wallet / the frontend.',
      inputSchema: {
        gameId: gameIdSchema,
        ...agentOpFields,
      },
    },
    async ({ gameId, sender, signature, userOp }) => {
      return submitUserOp(
        { sender, signature, userOp },
        {
          engine: lobby.address,
          abi: lobbyAbi,
          functionName: 'acceptChallenge',
          args: [gameId],
        },
      );
    },
  );

  tool(server,
    'modify_challenge',
    {
      title: 'Modify a pending challenge',
      description:
        'Counter-offer on a pending challenge: change seat, time-per-move, or wager amount. NOTE: not available under the 7702-only path (the Lobby paymaster sponsors only engine moves) — returns an error. Use an owner wallet / the frontend.',
      inputSchema: {
        gameId: gameIdSchema,
        startAsWhite: z.boolean(),
        timePerMove: bigUintSchema,
        wagerAmount: bigUintSchema,
        ...agentOpFields,
      },
    },
    async ({ gameId, startAsWhite, timePerMove, wagerAmount, sender, signature, userOp }) => {
      return submitUserOp(
        { sender, signature, userOp },
        {
          engine: lobby.address,
          abi: lobbyAbi,
          functionName: 'modifyChallenge',
          args: [gameId, startAsWhite, timePerMove, wagerAmount],
        },
      );
    },
  );

  tool(server,
    'decline_challenge',
    {
      title: 'Decline a pending challenge',
      description: 'Decline a pending challenge (refunds any deposited wager). NOTE: not available under the 7702-only path — returns an error. Use an owner wallet / the frontend.',
      inputSchema: { gameId: gameIdSchema, ...agentOpFields },
    },
    async ({ gameId, sender, signature, userOp }) => {
      return submitUserOp(
        { sender, signature, userOp },
        {
          engine: lobby.address,
          abi: lobbyAbi,
          functionName: 'declineChallenge',
          args: [gameId],
        },
      );
    },
  );

  tool(server,
    'withdraw',
    {
      title: 'Withdraw accumulated earnings',
      description:
        'Pull all withdrawable earnings of the given token out of the lobby (default ETH). NOTE: not available under the 7702-only path — returns an error. Withdraw from an owner wallet / the frontend.',
      inputSchema: { token: addressSchema.optional(), ...agentOpFields },
    },
    async ({ token, sender, signature, userOp }) => {
      const tok = (token ?? zeroAddress) as Address;
      return submitUserOp(
        { sender, signature, userOp },
        {
          engine: lobby.address,
          abi: lobbyAbi,
          functionName: 'withdraw',
          args: [tok],
        },
      );
    },
  );
}
