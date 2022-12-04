// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract DisputeGameTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'illegal');
    changePrank(p2);
  }

  modifier expectGameDisputed(address sender, address receiver) {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit GameDisputed(gameId, sender, receiver);
    _;
  }

  modifier testDispute() {
    changePrank(arbiter);
    uint nDisputes = lobby.disputes().length;
    changePrank(p2);
    _;
    changePrank(arbiter);
    GameData memory gameData = engine.game(gameId);
    assertTrue(gameData.state == GameState.Review);
    assertTrue(gameData.outcome == GameOutcome.Undecided);
    uint[] memory disputes = lobby.disputes();
    assertEq(disputes.length, nDisputes+1);
    assertEq(gameId, disputes[nDisputes]);
  }

  function _expectOutcome(GameOutcome outcome) private {
    GameData memory gameData = engine.game(gameId);
  }

  function testDisputeAsSender() public {
    changePrank(p1);
    vm.expectRevert('NotCurrentMove');
    engine.disputeGame(gameId);
  }

  function testDisputeAsReceiver() public
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, 0)
    testDispute()
    expectGameDisputed(p2, p1)
  {
    engine.disputeGame(gameId);
  }

  function testDisputeAsSpectator() public {
    changePrank(p3);
    vm.expectRevert('PlayerOnly');
    engine.disputeGame(gameId);
  }

  function testMoveFailsAfterDispute() public {
    testDisputeAsReceiver();
    vm.expectRevert('InvalidContractState');
    _move(p2, 'b6');
  }
}
