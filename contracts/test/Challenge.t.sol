// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import 'forge-std/console2.sol';
import 'src/Lobby.sol';
import 'src/ChessEngine.sol';
import 'test/Lobby.t.sol';

abstract contract ChallengeTest is LobbyTest {
  ChessEngine engine;
  uint gameId;

  constructor() {
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    engine = ChessEngine(lobby.engine());
    vm.stopPrank();
  }
}

contract AcceptChallengeTest is ChallengeTest {
  function setUp() public {
    vm.startPrank(p1);
    lobby.challenge{ value: wager }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges();
    gameId = challenges[0];
  }

  function _testAccepted(address player) public {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 1);
    assertEq(games[0], gameId);
  }

  function testAcceptAsPlayer1() public {
    changePrank(p1);
    vm.expectRevert('NotCurrentMove');
    engine.acceptChallenge{ value: wager }(gameId);
  }

  function testAcceptAsPlayer2() public {
    changePrank(p2);
    vm.expectEmit(true, true, true, true);
    emit GameStarted(gameId, p1, p2);
    engine.acceptChallenge{ value: wager }(gameId);
    _testAccepted(p1);
    _testAccepted(p2);
  }

  function testAcceptAsPlayer3() public {
    changePrank(p3);
    vm.expectRevert('NotCurrentMove');
    engine.acceptChallenge{ value: wager }(gameId);
  }
}

contract DeclineChallengeTest is ChallengeTest {
  function setUp() public {
    vm.startPrank(p1);
    lobby.challenge{ value: wager }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges();
    gameId = challenges[0];
  }

  function _testDeclined(address player) public {
    changePrank(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 0);
  }

  function testDeclineAsPlayer1() public {
    changePrank(p1);
    engine.declineChallenge(gameId);
    _testDeclined(p1);
    _testDeclined(p2);
  }

  function testDeclineAsPlayer2() public {
    changePrank(p2);
    engine.declineChallenge(gameId);
    _testDeclined(p1);
    _testDeclined(p2);
  }

  function testDeclineAsPlayer3() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.declineChallenge(gameId);
  }
}

contract ModifyChallengeTest is ChallengeTest {
  function setUp() public {
    vm.startPrank(p1);
    lobby.challenge{ value: wager }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges();
    gameId = challenges[0];
  }

  function testModifyColorAsPlayer1() public {
    changePrank(p1);
    engine.modifyChallenge(gameId, false, timePerMove, wager);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p2);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyColorAsPlayer2() public {
    changePrank(p2);
    engine.modifyChallenge(gameId, true, timePerMove, wager);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyTPMAsPlayer1() public {
    changePrank(p1);
    engine.modifyChallenge(gameId, true, timePerMove*2, wager);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.timePerMove, timePerMove*2);
  }

  function testModifyTPMAsPlayer2() public {
    changePrank(p2);
    engine.modifyChallenge(gameId, false, timePerMove*2, wager);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.timePerMove, timePerMove*2);
  }

  function testModifyWagerAsPlayer1() public {
    changePrank(p1);
    engine.modifyChallenge(gameId, true, timePerMove, wager*2);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p2);
    assertEq(gameData.wagerAmount, wager*2);
  }

  function testModifyWagerAsPlayer2() public {
    changePrank(p2);
    engine.modifyChallenge(gameId, true, timePerMove, wager/2);
    ChessEngine.GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.wagerAmount, wager/2);
  }

  function testModifyAsPlayer3() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.modifyChallenge(gameId, false, timePerMove*2, wager/2);
  }
}
