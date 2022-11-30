// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import './Challenge.t.sol';

abstract contract ChessGameTest is ChallengeTest {
  constructor() {
    setPlayer(p1);
    lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges();
    gameId = challenges[0];
    switchPlayer();
  }

  function _move(address player, string memory san) internal {
    setPlayer(player);
    engine.move(gameId, san);
  }

  function _testMove(address player, string memory san) internal {
    vm.expectEmit(true, true, true, true, address(engine));
    emit MoveSAN(gameId, player, san);
    _move(player, san);
    string[] memory moves = engine.moves(gameId);
    if (moves.length == 0) return;
    assertEq(moves[moves.length-1], san);
  }
}

contract StartGameTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function _testAccepted(address player) public {
    setPlayer(player);
    uint[] memory challenges = lobby.challenges();
    assertEq(challenges.length, 0);
    uint[] memory games = lobby.games();
    assertEq(games.length, 1);
    assertEq(games[0], gameId);
  }

  function testInitialGameData() public {
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Started));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    assertEq(gameData.whitePlayer, p1);
    assertEq(gameData.blackPlayer, p2);
    assertEq(gameData.currentMove, p1);
    assertEq(gameData.timePerMove, timePerMove);
    assertGt(gameData.timeOfLastMove, 0);
    assertEq(gameData.wagerAmount, wager);
  }

  function testFetchDataAsPlayer3() public
    asSpectator
  {
    testInitialGameData();
  }

  function testSomeLegalMoves() public {
    _testMove(p1, 'a3');
    _testMove(p2, 'b6');
    _testMove(p1, 'c4');
    _testMove(p2, 'd5');
  }

  function testFirstMoveAsBlackFails() public {
    vm.expectRevert('NotCurrentMove');
    _move(p2, 'b6');
  }

  function testConsecutiveMoveFails() public {
    _testMove(p1, 'a3');
    vm.expectRevert('NotCurrentMove');
    _move(p1, 'b4');
  }
}

contract ResignGameTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testResignAsSender() public
    asSender
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
  {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameOver(gameId, GameOutcome.WhiteWon, p1);
    engine.resign(gameId);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == GameOutcome.WhiteWon);
  }

  function testResignAsReceiver() public
    asReceiver
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, int(2*wager))
  {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameOver(gameId, GameOutcome.BlackWon, p2);
    engine.resign(gameId);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == GameOutcome.BlackWon);
  }

  function testResignAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.resign(gameId);
  }

  function testMoveFailsAfterResign() public {
    engine.resign(gameId);
    vm.expectRevert('InvalidContractState');
    _move(p1, 'a3');
  }
}

contract MoveTimerTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a3');
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.timeOfLastMove > 0);
  }

  function testTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    _testMove(p2, 'b6');
  }

  function testTimerAlmostExpired() public {
    skip(timePerMove);
    testTimerActive();
  }

  function testTimerExpired() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    vm.expectRevert('TimerExpired');
    _move(p2, 'b6');
  }
}

contract ClaimVictoryTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'a3');
  }

  function testClaimVictoryFailsWhileTimerActive() public {
    assertFalse(engine.timeDidExpire(gameId));
    vm.expectRevert('TimerActive');
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsWinner() public
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
  {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    switchPlayer();
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameOver(gameId, GameOutcome.WhiteWon, p1);
    engine.claimVictory(gameId);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == GameOutcome.WhiteWon);
  }

  function testClaimVictoryAsLoser() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    changePrank(p2);
    vm.expectRevert('NotOpponentsMove');
    engine.claimVictory(gameId);
  }

  function testClaimVictoryAsSpectator() public {
    skip(timePerMove+1);
    assertTrue(engine.timeDidExpire(gameId));
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.claimVictory(gameId);
  }
}

contract DrawGameTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
    switchPlayer();
    engine.offerDraw(gameId);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Draw));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
  }

  function testMoveFailsDuringDraw() public {
    vm.expectRevert('InvalidContractState');
    _move(p2, 'b6');
  }

  function testAcceptDraw() public
    asReceiver
    testBalanceDelta(p1, int(wager))
    testBalanceDelta(p2, int(wager))
  {
    engine.respondDraw(gameId, true);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Finished));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Draw));
  }

  function testDeclineDraw() public
    asReceiver
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, 0)
  {
    engine.respondDraw(gameId, false);
    GameData memory gameData = engine.game(gameId);
    assertEq(uint(gameData.state), uint(GameState.Started));
    assertEq(uint(gameData.outcome), uint(GameOutcome.Undecided));
    _testMove(p1, 'a3');
    _testMove(p2, 'b6');
  }

  function testRespondDrawFailsAsSender() public
    asSender
  {
    vm.expectRevert('NotCurrentMove');
    engine.respondDraw(gameId, true);
  }

  function testRespondDrawFailsAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.respondDraw(gameId, true);
  }
}

contract DisputeGameTest is ChessGameTest {
  function setUp() public
    syncReceiver
  {
    engine.acceptChallenge{ value: deposit }(gameId);
    // Perform a move (illegal but irrelevant for the sake of testing)
    _testMove(p1, 'Ne8');
  }

  function _expectGameDisputed() private {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit GameDisputed(gameId, p2, p1);
  }

  function _expectDisputeResolved() private {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit DisputeResolved(gameId, p1, p2);
  }

  function _expectDisputeRemoved() private {
    uint[] memory disputes = lobby.disputes();
    assertEq(disputes.length, 0);
  }

  function _expectDisputePushed() private {
    changePrank(arbiter);
    uint[] memory disputes = lobby.disputes();
    assertEq(disputes.length, 1);
    assertEq(disputes[disputes.length-1], gameId);
    changePrank(currentPlayer);
  }

  function _expectNoOutcome() private {
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Review);
    assertTrue(gameData.outcome == GameOutcome.Undecided);
  }

  function _expectOutcome(GameOutcome outcome) private {
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == outcome);
  }

  function testDisputeAsSender() public
    asSender
  {
    vm.expectRevert('NotCurrentMove');
    engine.disputeGame(gameId);
  }

  function testDisputeAsReceiver() public
    asReceiver
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, 0)
  {
    _expectGameDisputed();
    engine.disputeGame(gameId);
    _expectNoOutcome();
    _expectDisputePushed();
  }

  function testDisputeAsSpectator() public
    asSpectator
  {
    vm.expectRevert('PlayerOnly');
    engine.disputeGame(gameId);
  }

  function testMoveFailsAfterDispute() public {
    testDisputeAsReceiver();
    vm.expectRevert('InvalidContractState');
    _move(p2, 'b6');
  }

  function _testResolveDispute(GameOutcome outcome) public
    syncReceiver
  {
    testDisputeAsReceiver();
    changePrank(arbiter);
    _expectDisputeResolved();
    engine.resolveDispute(gameId, outcome);
    _expectOutcome(outcome);
    _expectDisputeRemoved();
  }

  function testResolveDisputeForWhite() public
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
  {
    _testResolveDispute(GameOutcome.WhiteWon);
  }

  function testResolveDisputeForBlack() public
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, int(2*wager))
  {
    _testResolveDispute(GameOutcome.BlackWon);
  }

  function testResolveDisputeAsDraw() public
    testBalanceDelta(p1, int(wager))
    testBalanceDelta(p2, int(wager))
  {
    _testResolveDispute(GameOutcome.Draw);
  }
}
