import { z } from 'zod';
import { zeroAddress, type Address, type Hash } from 'viem';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { lobby } from '../contracts/lobby.js';
import { botAddress, submit } from '../chain.js';
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
      const addr = (player ?? botAddress) as Address;
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
      const addr = (player ?? botAddress) as Address;
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
      const addr = (player ?? botAddress) as Address;
      const ids = (await lobby.read.history([addr])) as bigint[];
      return textResult({ player: addr, history: ids });
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
      const addr = (player ?? botAddress) as Address;
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
      const addr = (player ?? botAddress) as Address;
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
      description: 'Amount held in lobby escrow for a player on a given game (defaults to bot).',
      inputSchema: {
        gameId: gameIdSchema,
        player: addressSchema.optional(),
      },
    },
    async ({ gameId, player }) => {
      const addr = (player ?? botAddress) as Address;
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
        'Create a challenge against an opponent. wagerToken defaults to the zero address (ETH); for ETH games wagerAmount is sent as msg.value. ERC20 wagers require a prior approval (not handled here).',
      inputSchema: {
        opponent: addressSchema,
        startAsWhite: z.boolean().default(true),
        timePerMove: bigUintSchema.describe('Seconds allowed per move'),
        wagerAmount: bigUintSchema.default(0).describe('Wager in wei (or token base units)'),
        wagerToken: addressSchema.optional(),
      },
    },
    async ({ opponent, startAsWhite, timePerMove, wagerAmount, wagerToken }) => {
      const token = (wagerToken ?? zeroAddress) as Address;
      const value = token === zeroAddress ? wagerAmount : 0n;
      const hash = (await lobby.write.challenge(
        [opponent as Address, startAsWhite, timePerMove, wagerAmount, token],
        { value },
      )) as Hash;
      return textResult(await submit(hash));
    },
  );

  tool(server,
    'accept_challenge',
    {
      title: 'Accept a pending challenge',
      description:
        'Accept a pending challenge. The lobby will pull the wager into escrow if the bot has not already deposited it; pass `value` if a top-up is required for an ETH game.',
      inputSchema: {
        gameId: gameIdSchema,
        value: bigUintSchema.optional().describe('Wei to send with the call (for ETH top-up)'),
      },
    },
    async ({ gameId, value }) => {
      const hash = (await lobby.write.acceptChallenge([gameId], { value: value ?? 0n })) as Hash;
      return textResult(await submit(hash));
    },
  );

  tool(server,
    'modify_challenge',
    {
      title: 'Modify a pending challenge',
      description:
        'Counter-offer on a pending challenge: change seat, time-per-move, or wager amount. The contract bumps currentMove to the opponent so they can re-accept.',
      inputSchema: {
        gameId: gameIdSchema,
        startAsWhite: z.boolean(),
        timePerMove: bigUintSchema,
        wagerAmount: bigUintSchema,
        value: bigUintSchema.optional().describe('Wei to send if the new wager requires a top-up'),
      },
    },
    async ({ gameId, startAsWhite, timePerMove, wagerAmount, value }) => {
      const hash = (await lobby.write.modifyChallenge(
        [gameId, startAsWhite, timePerMove, wagerAmount],
        { value: value ?? 0n },
      )) as Hash;
      return textResult(await submit(hash));
    },
  );

  tool(server,
    'decline_challenge',
    {
      title: 'Decline a pending challenge',
      description: 'Decline a pending challenge. Refunds any deposited wager.',
      inputSchema: { gameId: gameIdSchema },
    },
    async ({ gameId }) => {
      const hash = (await lobby.write.declineChallenge([gameId])) as Hash;
      return textResult(await submit(hash));
    },
  );

  tool(server,
    'withdraw',
    {
      title: 'Withdraw accumulated earnings',
      description:
        'Pull all withdrawable earnings of the given token out of the lobby. Default token is the zero address (ETH).',
      inputSchema: { token: addressSchema.optional() },
    },
    async ({ token }) => {
      const tok = (token ?? zeroAddress) as Address;
      const hash = (await lobby.write.withdraw([tok])) as Hash;
      return textResult(await submit(hash));
    },
  );
}
