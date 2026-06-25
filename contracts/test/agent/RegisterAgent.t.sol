// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '../Lobby.t.sol';

contract RegisterAgentTest is LobbyTest {
  address a1;
  address a2;

  function setUp() public {
    a1 = makeAddr('agent1');
    a2 = makeAddr('agent2');
    changePrank(p1);
  }

  function testRegisterAgent() public {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentRegistered(p1, a1);
    lobby.registerAgent(a1, 'deepblue', 'ipfs://avatar', 'Hermes', 'Claude Opus', '4.7');

    assertEq(lobby.agentProfile(a1).owner, p1);
    assertTrue(lobby.hasRole(lobby.AGENT_ROLE(), a1));

    address[] memory list = lobby.agents(p1);
    assertEq(list.length, 1);
    assertEq(list[0], a1);

    RobotProfile memory profile = lobby.agentProfile(a1);
    assertEq(profile.owner, p1);
    assertTrue(profile.active);
    assertEq(profile.nickname, 'deepblue');
    assertEq(profile.agentFramework, 'Hermes');
    assertEq(profile.baseModel, 'Claude Opus');
    assertEq(profile.modelVersion, '4.7');
  }

  function testRegisterRevertsWhenOwned() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');

    // Same owner can't re-register.
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerAgent(a1, 'bot', '', '', '', '');

    // Nor can a different account claim it (hijack guard).
    changePrank(p3);
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerAgent(a1, 'bot', '', '', '', '');
  }

  function testRegisterRejectsPlayer() public {
    // Creating a challenge registers both participants as players...
    changePrank(arbiter);
    lobby.allowChallenges(true);
    changePrank(p1);
    lobby.challenge(p1, p2, true, timePerMove, 0, address(0));

    // ...so neither can then be claimed as someone else's agent.
    changePrank(p3);
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerAgent(p1, 'bot', '', '', '', '');
    vm.expectRevert(AlreadyRegistered.selector);
    lobby.registerAgent(p2, 'bot', '', '', '', '');
  }

  function testUnregister() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');

    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentUnregistered(p1, a1);
    lobby.unregisterAgent(a1);

    // a1 is unregistered now (agentProfile would revert isRegistered), so verify via role + set.
    assertFalse(lobby.hasRole(lobby.AGENT_ROLE(), a1));
    assertEq(lobby.agents(p1).length, 0);
  }

  function testUnregisterNotOwner() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    changePrank(p3);
    vm.expectRevert(Unauthorized.selector);
    lobby.unregisterAgent(a1);
  }

  function testAgentProfileRejectsPlayer() public {
    // A registered player is not an agent — agentProfile rejects it.
    vm.expectRevert(Unauthorized.selector);
    lobby.agentProfile(p2);
  }

  function testMultipleAgents() public {
    lobby.registerAgent(a1, 'a', '', '', '', '');
    lobby.registerAgent(a2, 'b', '', '', '', '');
    assertEq(lobby.agents(p1).length, 2);

    lobby.unregisterAgent(a1);
    address[] memory list = lobby.agents(p1);
    assertEq(list.length, 1);
    assertEq(list[0], a2);
  }

  function testUpdateAgent() public {
    lobby.registerAgent(a1, 'deepblue', 'ipfs://old', 'Hermes', 'Claude Opus', '4.6');

    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentUpdated(p1, a1);
    lobby.updateAgent(a1, 'alphazero', 'ipfs://new', 'LangChain', 'Claude Sonnet', '4.7');

    RobotProfile memory profile = lobby.agentProfile(a1);
    assertEq(profile.nickname, 'alphazero');
    assertEq(profile.avatar, 'ipfs://new');
    assertEq(profile.agentFramework, 'LangChain');
    assertEq(profile.baseModel, 'Claude Sonnet');
    assertEq(profile.modelVersion, '4.7');
    // An update touches only the profile fields, not ownership or active state.
    assertEq(profile.owner, p1);
    assertTrue(profile.active);
  }

  function testUpdateAgentNotOwner() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    changePrank(p3);
    vm.expectRevert(Unauthorized.selector);
    lobby.updateAgent(a1, 'hijacked', '', '', '', '');
  }

  function testAgentUpdatesOwnProfile() public {
    lobby.registerAgent(a1, 'deepblue', 'ipfs://old', 'Hermes', 'Claude Opus', '4.6');

    changePrank(a1);
    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentUpdated(a1, a1);
    lobby.updateAgent(a1, 'alphazero', 'ipfs://new', 'LangChain', 'Claude Sonnet', '4.7');

    assertEq(lobby.agentProfile(a1).nickname, 'alphazero');
    assertEq(lobby.agentProfile(a1).modelVersion, '4.7');
    assertEq(lobby.agentProfile(a1).owner, p1);
  }

  function testAgentCannotUpdateSibling() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    lobby.registerAgent(a2, 'bot', '', '', '', '');
    changePrank(a1);
    vm.expectRevert(Unauthorized.selector);
    lobby.updateAgent(a2, 'hijacked', '', '', '', '');
  }

  function testUpdateUnregisteredAgent() public {
    // updateAgent → _assertSenderControls(a1) rejects acting on an unregistered agent.
    vm.expectRevert(Unauthorized.selector);
    lobby.updateAgent(a1, 'bot', '', '', '', '');
  }

  function testSuspendThenResume() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    assertTrue(lobby.agentProfile(a1).active);

    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentSuspended(p1, a1);
    lobby.suspendAgent(a1);
    assertFalse(lobby.agentProfile(a1).active);

    // suspend/resume are now distinct entry points; resumeAgent re-activates.
    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentResumed(p1, a1);
    lobby.resumeAgent(a1);
    assertTrue(lobby.agentProfile(a1).active);
  }

  function testSuspendAgentNotOwner() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    changePrank(p3);
    vm.expectRevert(Unauthorized.selector);
    lobby.suspendAgent(a1);
  }

  function testBannedCannotRegister() public {
    changePrank(arbiter);
    lobby.grantRole(lobby.BANNED_ROLE(), p1);
    changePrank(p1);
    vm.expectRevert(UserBanned.selector);
    lobby.registerAgent(a1, 'bot', '', '', '', '');
  }

  function testReRegisterAfterUnregister() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    lobby.unregisterAgent(a1);

    // The same owner can register it again.
    lobby.registerAgent(a1, 'bot2', '', '', '', '');
    assertEq(lobby.agentProfile(a1).owner, p1);
    assertTrue(lobby.hasRole(lobby.AGENT_ROLE(), a1));

    // After releasing it, a different owner can claim it.
    lobby.unregisterAgent(a1);
    changePrank(p3);
    lobby.registerAgent(a1, 'bot3', '', '', '', '');
    assertEq(lobby.agentProfile(a1).owner, p3);
  }
}
