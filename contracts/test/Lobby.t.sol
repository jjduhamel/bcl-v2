// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Test.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';

abstract contract LobbyTest is Test, LobbyInterface, ChessEngineInterface {
  Lobby lobby;
  ChessEngine engine;
  address arbiter;
  address p1;
  address p2;
  address p3;
  uint timePerMove = 300;
  uint wager = 1 ether;

  function _initializeLobby() private {
    Lobby lobbyImpl = new Lobby();
    ERC1967Proxy proxy = new ERC1967Proxy(address(lobbyImpl), '');
    lobby = Lobby(address(proxy));
    lobby.initialize();
  }

  function _initializeEngine() private {
    ChessEngine engineImpl = new ChessEngine();
    ERC1967Proxy proxy = new ERC1967Proxy(address(engineImpl), '');
    engine = ChessEngine(address(proxy));
    engine.initialize(address(lobby));
    lobby.setChessEngine(address(engine));
  }

  constructor() {
    arbiter = makeAddr('arbiter');
    p1 = makeAddr('player1');
    vm.deal(p1, 100 ether);
    p2 = makeAddr('player2');
    vm.deal(p2, 100 ether);
    p3 = makeAddr('player3');
    vm.deal(p3, 100 ether);
    vm.startPrank(arbiter);
    _initializeLobby();
    _initializeEngine();
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
    lobby.challenge(p2, true, 60, 10);
  }
}

contract WageringDisabledTest is LobbyTest {
  function setUp() public {
    lobby.allowChallenges(true);
    changePrank(p1);
  }

  function testChallengeWithoutWager() public {
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, p1, p2);
    lobby.challenge(p2, true, 60, 0);
  }

  function _testPlayerLobby(address player) private returns (uint[] memory) {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 1);
    return challenges;
  }

  function testPlayersReceiveChallenge() public {
    lobby.challenge(p2, true, 60, 0);
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
    vm.expectEmit(false, false, false, false, address(lobby));
    emit NewChallenge(0, p1, p2);
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
    lobby.challenge{ value: wager/2 }(p2, true, 60, wager);
  }

  function testExcessDepositAmount() public {
    lobby.challenge{ value: wager*2 }(p2, true, 60, wager);
    // TODO
  }
}
