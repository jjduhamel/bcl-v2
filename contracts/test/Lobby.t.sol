// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Test.sol';
import '@forge/console2.sol';
import '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';

contract WhoAmI {
  function who() public returns (address) {
    return msg.sender;
  }
}

abstract contract LobbyTest is Test, ILobby, IChessEngine {
  WhoAmI me;
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
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(lobbyImpl),
      abi.encodeCall(Lobby.initialize, (arbiter))
    );
    lobby = Lobby(address(proxy));
  }

  function _initializeEngine() private {
    ChessEngine engineImpl = new ChessEngine();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(engineImpl),
      abi.encodeCall(ChessEngine.initialize, (address(lobby)))
    );
    engine = ChessEngine(address(proxy));
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
    me = new WhoAmI();
    vm.startPrank(arbiter);
    _initializeLobby();
    _initializeEngine();
    lobby.registerPlayer(p1, '', '');
    lobby.registerPlayer(p2, '', '');
    lobby.registerPlayer(p3, '', '');
  }

  function fee() internal view returns (uint) {
    return wager * lobby.platformFeePerc() / 100;
  }

  function purse() internal view returns (uint) {
    return 2 * (wager - fee());
  }

  function totalWagers(address player) internal returns (uint) {
    address i = me.who();
    changePrank(player);
    Escrow.EscrowStats memory stats = lobby.wagerStats(player, address(0));
    changePrank(i);
    return stats.wagers;
  }

  function totalWinnings(address player) internal returns (uint) {
    address i = me.who();
    changePrank(player);
    Escrow.EscrowStats memory stats = lobby.wagerStats(player, address(0));
    changePrank(i);
    return stats.earnings;
  }

  function totalLosses(address player) internal returns (uint) {
    address i = me.who();
    changePrank(player);
    Escrow.EscrowStats memory stats = lobby.wagerStats(player, address(0));
    changePrank(i);
    return stats.losses;
  }
}

contract ChallengingDisabledTest is LobbyTest {
  function setUp() public {
    changePrank(p1);
  }

  function testArbiterIsCorrect() public {
    bool isArbiter = lobby.hasRole(lobby.ARBITER_ROLE(), arbiter);
    assertTrue(isArbiter);
  }

  function testChallengeDisabled() public {
    vm.expectRevert(ChallengingDisabled.selector);
    lobby.challenge(p1, p2, true, 60, 10, address(0));
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
    lobby.challenge(p1, p2, true, 60, 0, address(0));
  }

  function _testPlayerLobby(address player) private returns (uint[] memory) {
    changePrank(player);
    uint[] memory challenges = lobby.challenges(player);
    assertEq(challenges.length, 1);
    return challenges;
  }

  function testPlayersReceiveChallenge() public {
    lobby.challenge(p1, p2, true, 60, 0, address(0));
    uint[] memory c1 = _testPlayerLobby(p1);
    uint[] memory c2 = _testPlayerLobby(p2);
    assertEq(c1, c2);
  }

  function testWageringDisabled() public {
    vm.expectRevert(WageringDisabled.selector);
    lobby.challenge{ value: wager }(p1, p2, true, 60, wager, address(0));
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
    lobby.challenge{ value: wager }(p1, p2, true, 60, wager, address(0));
  }

  function _testPlayerLobby(address player) private returns (uint[] memory) {
    changePrank(player);
    uint[] memory challenges = lobby.challenges(player);
    assertEq(challenges.length, 1);
    return challenges;
  }

  function testPlayersReceiveChallenge() public {
    lobby.challenge{ value: wager }(p1, p2, true, 60, wager, address(0));
    uint[] memory c1 = _testPlayerLobby(p1);
    uint[] memory c2 = _testPlayerLobby(p2);
    assertEq(c1, c2);
  }

  function testInsufficientDepositAmount() public {
    vm.expectRevert(Escrow.InsufficientBalance.selector);
    lobby.challenge{ value: wager/2 }(p1, p2, true, 60, wager, address(0));
  }

}

contract BanUserTest is LobbyTest {
  function setUp() public {
    lobby.allowChallenges(true);
    lobby.grantRole(lobby.BANNED_ROLE(), p1);
    changePrank(p1);
  }

  function testChallengeFails() public {
    vm.expectRevert(UserBanned.selector);
    lobby.challenge(p1, p2, true, 60, 0, address(0));
  }

  function testUnbanUser() public {
    changePrank(arbiter);
    lobby.revokeRole(lobby.BANNED_ROLE(), p1);
    changePrank(p1);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, p1, p2);
    lobby.challenge(p1, p2, true, 60, 0, address(0));
  }
}

contract PlatformFeeTest is LobbyTest {
  function testInitialFeeIsTwoPercent() public {
    assertEq(lobby.platformFeePerc(), 2);
  }

  function testAdminCanSetFee() public {
    lobby.setPlatformFee(5);
    assertEq(lobby.platformFeePerc(), 5);
  }

  function testNonAdminCannotSetFee() public {
    changePrank(p1);
    vm.expectRevert(AdminOnly.selector);
    lobby.setPlatformFee(5);
  }
}

contract GasFeeTest is LobbyTest {
  function testInitialGasFeeIsTenPercent() public {
    assertEq(lobby.gasFeePerc(), 10);
  }

  function testAdminCanSetGasFee() public {
    lobby.setGasFee(15);
    assertEq(lobby.gasFeePerc(), 15);
  }

  function testNonAdminCannotSetGasFee() public {
    changePrank(p1);
    vm.expectRevert(AdminOnly.selector);
    lobby.setGasFee(15);
  }
}

contract EngineGetterPermissionsTest is LobbyTest {
  function testPlayerCantQueryAnotherDeposit() public {
    changePrank(p1);
    vm.expectRevert(ArbiterOnly.selector);
    lobby.checkPlayerDeposit(1, p2);
  }

  function testPlayerCantQueryOwnDepositViaTwoArgForm() public {
    changePrank(p1);
    vm.expectRevert(ArbiterOnly.selector);
    lobby.checkPlayerDeposit(1, p1);
  }

  function testArbiterCanQueryAnyBalance() public {
    // arbiter holds ADMIN_ROLE from initializer; isArbiter accepts admin
    assertEq(lobby.checkPlayerDeposit(1, p1), 0);
    assertEq(lobby.checkPlayerDeposit(1, p2), 0);
  }

  function testPlayerCantQueryAnotherEarnings() public {
    changePrank(p1);
    vm.expectRevert(AdminOnly.selector);
    lobby.checkPlayerEarnings(p2, address(0));
  }

  function testPlayerCantQueryOwnEarningsViaTwoArgForm() public {
    changePrank(p1);
    vm.expectRevert(AdminOnly.selector);
    lobby.checkPlayerEarnings(p1, address(0));
  }

  function testArbiterCanQueryAnyEarnings() public {
    assertEq(lobby.checkPlayerEarnings(p1, address(0)), 0);
    assertEq(lobby.checkPlayerEarnings(p2, address(0)), 0);
  }
}
