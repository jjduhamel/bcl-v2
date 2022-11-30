// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import './Lobby.t.sol';

abstract contract ChallengeTest is LobbyTest {
  uint gameId;
  address currentPlayer;

  constructor() {
    changePrank(arbiter);
    lobby.allowChallenges(true);
    lobby.allowWagers(true);
    setPlayer(p1);
  }

  modifier testBalanceDelta(address player, int delta) {
    int initialBalance = int(player.balance);
    _;
    assertEq(int(player.balance)-initialBalance, delta);
  }

  function setPlayer(address player) internal {
    currentPlayer = player;
    changePrank(currentPlayer);
  }

  function switchPlayer() internal returns (address) {
    setPlayer(currentPlayer == p1 ? p2 : p1);
    return currentPlayer;
  }

  modifier asSender() {
    setPlayer(engine.game(gameId).currentMove);
    switchPlayer();
    _;
  }

  modifier asReceiver() {
    setPlayer(engine.game(gameId).currentMove);
    _;
  }

  modifier asSpectator() {
    setPlayer(p3);
    _;
  }

  modifier syncReceiver() {
    _;
    currentPlayer = engine.game(gameId).currentMove;
  }

  function _testChallenge(uint id) internal {
    uint[] memory challenges = lobby.challenges();
    assertEq(id, challenges[challenges.length-1]);
  }
}

contract CreateChallengeTest is ChallengeTest {
  function testChallengeWithoutWager() public {
    gameId = lobby.challenge(p2, true, timePerMove, 0);
    _testChallenge(gameId);
  }

  function testChallengeWithWager() public
    testBalanceDelta(p1, -int(deposit))
  {
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    _testChallenge(gameId);
  }

  function testChallengeSucceedsWithMinimumTPM() public {
    lobby.challenge(p2, true, 60, 0);
    _testChallenge(gameId);
  }

  function testChallengeFailsWithInvalidTPM() public {
    vm.expectRevert('InvalidTimePerMove');
    lobby.challenge(p2, true, 59, 0);
  }

  function testChallengeFailsWithNoDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    lobby.challenge(p2, true, timePerMove, wager);
  }

  function testChallengeFailsWithLowDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    gameId = lobby.challenge{ value: deposit-1 }(p2, true, timePerMove, wager);
  }

  function testChallengeSucceedsWithExcessDeposit() public
    testBalanceDelta(p1, -int(deposit+1))
  {
    gameId = lobby.challenge{ value: deposit+1 }(p2, true, timePerMove, wager);
    _testChallenge(gameId);
  }
}

contract AcceptChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    switchPlayer();
  }

  function _expectGameStarted() public {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameStarted(gameId, p1, p2);
  }

  function _testAccepted(address player) public {
    setPlayer(player);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Started);
    assertTrue(gameData.outcome == GameOutcome.Undecided);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 1);
    assertEq(games[0], gameId);
  }

  function _testAccepted() public {
    _testAccepted(p1);
    _testAccepted(p2);
  }

  function testAcceptWithDeposit() public {
    _expectGameStarted();
    engine.acceptChallenge{ value: deposit }(gameId);
    _testAccepted();
  }

  function testAcceptFailsWithoutDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    engine.acceptChallenge(gameId);
  }

  function testAcceptFailsWithLowDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    engine.acceptChallenge{ value: deposit-1 }(gameId);
  }

  function testAcceptWithExcessDeposit() public {
    _expectGameStarted();
    engine.acceptChallenge{ value: deposit+1 }(gameId);
    _testAccepted();
  }

  function testAcceptFailsAsSender() public
    asSender
  {
    vm.expectRevert('NotCurrentMove');
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testAcceptAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testAcceptDisbursesExcessFunds() public
    asReceiver
    testBalanceDelta(p1, int(deposit/2))
    testBalanceDelta(p2, -int(deposit/2))
  {
    engine.modifyChallenge{ value: wager*2+fee }(gameId, true, timePerMove, wager/2);
    switchPlayer();
    engine.acceptChallenge(gameId);
  }

  function testAcceptFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.acceptChallenge(gameId);
  }

  function testDeclineFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.declineChallenge(gameId);
  }

  function testModifyFailsAfterAccept() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    vm.expectRevert('InvalidContractState');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }
}

contract DeclineChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    switchPlayer();
  }

  function _testDeclined(address player) public {
    setPlayer(player);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == GameOutcome.Declined);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 0);
    // Don't put these in the player history
    uint[] memory history = lobby.history();
    assertEq(history.length, 0);
  }

  function _expectDeclinedEvent(address player) private {
    vm.expectEmit(false, true, true, true, address(lobby));
    if (player == p1) emit ChallengeDeclined(0, p1, p2);
    else emit ChallengeDeclined(0, p2, p1);
  }

  function testDeclineAsSender() public
    asSender
    testBalanceDelta(p1, int(deposit))
    testBalanceDelta(p2, 0)
  {
    _expectDeclinedEvent(p1);
    engine.declineChallenge(gameId);
    _testDeclined(p1);
    _testDeclined(p2);
  }

  function testDeclineAsReceiver() public
    asReceiver
    testBalanceDelta(p1, int(deposit))
    testBalanceDelta(p2, 0)
  {
    _expectDeclinedEvent(p2);
    engine.declineChallenge(gameId);
    _testDeclined(p1);
    _testDeclined(p2);
  }

  function testDeclineAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.declineChallenge(gameId);
  }

  function testAcceptFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.acceptChallenge(gameId);
  }

  function testDeclineFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.declineChallenge(gameId);
  }

  function testModifyFailsAfterDecline() public {
    engine.declineChallenge(gameId);
    vm.expectRevert('InvalidContractState');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }
}

contract ModifyChallengeTest is ChallengeTest {
  function setUp() public {
    gameId = lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    switchPlayer();
  }

  function _expectTouchRecord(address player) private {
    //vm.expectEmit(false, true, true, true, address(lobby));
    //if (player == p1) emit TouchRecord(0, p1, p2);
    //else emit TouchRecord(0, p2, p1);
  }

  function testModifyColor() public {
    _expectTouchRecord(p2);
    engine.modifyChallenge{ value: deposit }(gameId, true, timePerMove, wager);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyColorAsSender() public
    asSender
  {
    _expectTouchRecord(p1);
    engine.modifyChallenge(gameId, false, timePerMove, wager);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(0));
    assertEq(gameData.currentMove, p2);
    assertEq(gameData.whitePlayer, p2);
    assertEq(gameData.blackPlayer, p1);
  }

  function testModifyFailsWithoutDeposit() public
    asReceiver
  {
    vm.expectRevert('InvalidDepositAmount');
    engine.modifyChallenge(gameId, true, timePerMove, wager);
  }

  function testModifyFailsWithLowDeposit() public
    asReceiver
  {
    GameData memory data = engine.game(gameId);
    assertTrue(data.state == GameState.Pending);
    vm.expectRevert('InvalidDepositAmount');
    engine.modifyChallenge{ value: deposit-1 }(gameId, true, timePerMove, wager);
  }

  function testModifyTimePerMove() public
    testBalanceDelta(p2, -int(deposit))
  {
    _expectTouchRecord(p2);
    engine.modifyChallenge{ value: deposit }(gameId, false, timePerMove-1, wager);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.timePerMove, timePerMove-1);
  }

  function testModifyInvalidTPMFails() public {
    vm.expectRevert('InvalidTimePerMove');
    engine.modifyChallenge{ value: deposit }(gameId, false, 59, wager);
  }

  function testModifyWager() public
    testBalanceDelta(p2, -int(deposit-1))
  {
    _expectTouchRecord(p2);
    engine.modifyChallenge{ value: deposit-1 }(gameId, true, timePerMove, wager-1);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.wagerAmount, wager-1);
  }

  function testIncreaseWagerAsSender() public
    asSender
    testBalanceDelta(p1, -int(deposit))
  {
    _expectTouchRecord(p1);
    engine.modifyChallenge{ value: deposit }(gameId, true, timePerMove, wager*2);
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.wagerAmount, wager*2);
  }

  function testModifyWagerFailsWithoutDeposit() public {
    vm.expectRevert('InvalidDepositAmount');
    engine.modifyChallenge(gameId, true, timePerMove, wager*2);
  }

  function testModifyFailsAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.modifyChallenge(gameId, false, timePerMove*2, wager/2);
  }
}
