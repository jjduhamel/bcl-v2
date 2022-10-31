// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import 'forge-std/console2.sol';
import 'src/Lobby.sol';

abstract contract LobbyTest is Test, LobbyEvents {
  Lobby lobby;
  address arbiter;
  address p1;
  address p2;
  address p3;
  uint timePerMove = 60;
  uint wager = 0.1 ether;

  constructor() {
    arbiter = makeAddr('arbiter');
    p1 = makeAddr('player1');
    vm.deal(p1, 100 ether);
    p2 = makeAddr('player2');
    vm.deal(p2, 100 ether);
    p3 = makeAddr('player3');
    vm.deal(p3, 100 ether);

    vm.startPrank(arbiter);
    lobby = new Lobby();
    lobby.initialize(arbiter);
  }
}

contract ChallengingDisabledTest is LobbyTest {
  function setUp() public {
    changePrank(p1);
  }

  function testArbiterIsCorrect() public {
    address out = lobby.arbiter();
    assertEq(out, arbiter);
  }

  function testChallengeDisabled() public {
    vm.expectRevert('ChallengingDisabled');
    lobby.challenge(p2, true, 10, 60);
  }
}

contract WageringDisabledTest is LobbyTest {
  function setUp() public {
    lobby.allowChallenges(true);
    changePrank(p1);
  }

  function testChallengeWithoutWager() public {
    vm.expectEmit(false, true, true, true);
    emit CreatedChallenge(0, p1, p2);
    lobby.challenge(p2, true, 0, 60);
  }

  function _testPlayerLobby(address player) private returns (uint[] memory) {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 1);
    return challenges;
  }

  function testPlayersReceiveChallenge() public {
    lobby.challenge(p2, true, 0, 60);
    uint[] memory c1 = _testPlayerLobby(p1);
    uint[] memory c2 = _testPlayerLobby(p2);
    assertEq(c1, c2);
  }

  function testWageringDisabled() public {
    vm.expectRevert('WageringDisabled');
    lobby.challenge{ value: wager }(p2, true, wager, 60);
  }
}

contract WageringEnabledTest is LobbyTest {
  function setUp() public {
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    changePrank(p1);
  }

  function testChallengeWithWager() public {
    vm.expectEmit(false, false, false, false);
    emit CreatedChallenge(0, p1, p2);
    lobby.challenge{ value: wager }(p2, true, wager, 60);
  }

  function _testPlayerLobby(address player) private returns (uint[] memory) {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 1);
    return challenges;
  }

  function testPlayersReceiveChallenge() public {
    lobby.challenge{ value: wager }(p2, true, wager, 60);
    uint[] memory c1 = _testPlayerLobby(p1);
    uint[] memory c2 = _testPlayerLobby(p2);
    assertEq(c1, c2);
  }

  function testInsufficientDepositAmount() public {
    vm.expectRevert('InvalidDepositAmount');
    lobby.challenge{ value: wager/2 }(p2, true, wager, 60);
  }

  function testExcessDepositAmount() public {
    lobby.challenge{ value: wager*2 }(p2, true, wager, 60);
    // TODO
  }
}
