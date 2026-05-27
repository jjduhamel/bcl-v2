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

    assertEq(lobby.ownerOf(a1), p1);
    assertTrue(lobby.hasRole(lobby.ROBOT_ROLE(), a1));

    address[] memory list = lobby.agents(p1);
    assertEq(list.length, 1);
    assertEq(list[0], a1);

    Lobby.RobotProfile memory profile = lobby.agent(a1);
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
    vm.expectRevert(AgentAlreadyRegistered.selector);
    lobby.registerAgent(a1, 'bot', '', '', '', '');

    // Nor can a different account claim it (hijack guard).
    changePrank(p3);
    vm.expectRevert(AgentAlreadyRegistered.selector);
    lobby.registerAgent(a1, 'bot', '', '', '', '');
  }

  function testUnregister() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');

    vm.expectEmit(true, true, true, true, address(lobby));
    emit AgentUnregistered(p1, a1);
    lobby.unregisterAgent(a1);

    assertEq(lobby.ownerOf(a1), a1);
    assertFalse(lobby.hasRole(lobby.ROBOT_ROLE(), a1));
    assertEq(lobby.agents(p1).length, 0);
  }

  function testUnregisterNotOwner() public {
    lobby.registerAgent(a1, 'bot', '', '', '', '');
    changePrank(p3);
    vm.expectRevert(NotAgentOwner.selector);
    lobby.unregisterAgent(a1);
  }

  function testOwnerOfPlainAddress() public {
    assertEq(lobby.ownerOf(p2), p2);
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
    assertEq(lobby.ownerOf(a1), p1);
    assertTrue(lobby.hasRole(lobby.ROBOT_ROLE(), a1));

    // After releasing it, a different owner can claim it.
    lobby.unregisterAgent(a1);
    changePrank(p3);
    lobby.registerAgent(a1, 'bot3', '', '', '', '');
    assertEq(lobby.ownerOf(a1), p3);
  }
}
