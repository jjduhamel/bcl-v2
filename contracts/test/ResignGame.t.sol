// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract ResignGameTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  modifier testResign(GameOutcome outcome, address winner) {
    vm.expectEmit(true, true, true, true, address(engine));
    emit GameOver(gameId, outcome, winner);
    _;
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Finished);
    assertTrue(gameData.outcome == outcome);
  }

  function testResignAsWhite() public
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, int(2*wager))
    testResign(GameOutcome.BlackWon, p2)
  {
    changePrank(p1);
    engine.resign(gameId);
  }

  function testResignAsBlack() public
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
    testResign(GameOutcome.WhiteWon, p1)
  {
    changePrank(p2);
    engine.resign(gameId);
  }

  function testResignAsSpectator() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.resign(gameId);
  }

  function testMoveFailsAfterResign() public {
    engine.resign(gameId);
    vm.expectRevert('InvalidContractState');
    _move(p1, 'a3');
  }
}
