// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '../Lobby.t.sol';

// registerPlayer + the isRegistered/isUnregistered guards that close the mid-game
// owner-flip theft: an address must register before it can play or own agents, and a
// registered player/agent can't be (re)claimed as an agent.
contract RegisterPlayerTest is LobbyTest {
  address u;   // fresh, never registered (p1/p2/p3 are pre-registered by LobbyTest)
  address ag;  // fresh, used to register an agent

  function setUp() public {
    u = makeAddr('unregistered');
    ag = makeAddr('agent');
    changePrank(p1);
  }

  /*
   * registerPlayer
   */

  function testRegisterPlayer() public {
    changePrank(u);
    lobby.registerPlayer(u, 'neo', 'ipfs://avatar');

    ProfileLib.PlayerProfile memory p = lobby.playerProfile(u);
    assertEq(p.username, 'neo');
    assertEq(p.avatar, 'ipfs://avatar');
    assertTrue(p.createdAt != 0);
  }

  function testRegisterPlayerRevertsWhenAlreadyPlayer() public {
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerPlayer(p1, 'dup', '');
  }

  function testRegisterPlayerRevertsWhenAgent() public {
    lobby.registerAgent(ag, 'bot', '', '', '', '');
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerPlayer(ag, 'x', '');
  }

  function testRegisterPlayerTwiceReverts() public {
    lobby.registerPlayer(u, 'neo', '');
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerPlayer(u, 'neo2', '');
  }

  /*
   * isRegistered guards — an unregistered address can't play or own agents.
   * (acceptChallenge/modifyChallenge/declineChallenge's isRegistered(msg.sender) is
   *  unreachable by an unregistered caller — you must already be a registered game party.)
   */

  function testChallengeRevertsUnregisteredSender() public {
    changePrank(arbiter);
    lobby.allowChallenges(true);
    changePrank(u);
    // isOwner(sender) → ownerOf(u) → isRegistered(u) reverts.
    vm.expectRevert(Unregistered.selector);
    lobby.challenge(u, p2, true, timePerMove, 0, address(0));
  }

  function testChallengeRevertsUnregisteredOpponent() public {
    changePrank(arbiter);
    lobby.allowChallenges(true);
    changePrank(p1);
    vm.expectRevert(Unregistered.selector);
    lobby.challenge(p1, u, true, timePerMove, 0, address(0));
  }

  function testRegisterAgentRevertsUnregisteredOwner() public {
    changePrank(u);
    vm.expectRevert(Unregistered.selector);
    lobby.registerAgent(ag, 'bot', '', '', '', '');
  }

  function testPlayerProfileRevertsUnregistered() public {
    vm.expectRevert(Unregistered.selector);
    lobby.playerProfile(u);
  }

  function testAgentProfileRevertsUnregistered() public {
    vm.expectRevert(Unregistered.selector);
    lobby.agentProfile(u);
  }
}
