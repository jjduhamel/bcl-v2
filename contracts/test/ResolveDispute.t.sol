// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract ResolveDisputeTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
    _testMove(p1, 'illegal');
    changePrank(p2);
    engine.disputeGame(gameId);
    changePrank(arbiter);
  }

  modifier expectDisputeResolved(address sender, address receiver) {
    vm.expectEmit(true, true, true, true, address(lobby));
    emit DisputeResolved(gameId, sender, receiver);
    _;
  }

  modifier testResolved() {
    address i = me.who();
    changePrank(arbiter);
    uint nDisputes = lobby.disputes().length;
    changePrank(i);
    _;
    changePrank(arbiter);
    uint[] memory disputes = lobby.disputes();
    assertEq(disputes.length, nDisputes-1);
  }

  function testResolveDisputeForWhite() public
    testOutcome(GameOutcome.WhiteWon)
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
    testWinner(p1)
    testLoser(p2)
    testResolved
    expectDisputeResolved(p1, p2)
  {
    engine.resolveDispute(gameId, GameOutcome.WhiteWon);
  }

  function testResolveDisputeForBlack() public
    testOutcome(GameOutcome.BlackWon)
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, int(2*wager))
    testLoser(p1)
    testWinner(p2)
    testResolved
    expectDisputeResolved(p1, p2)
  {
    engine.resolveDispute(gameId, GameOutcome.BlackWon);
  }

  function testResolveDisputeAsDraw() public
    testOutcome(GameOutcome.Draw)
    testBalanceDelta(p1, int(wager))
    testBalanceDelta(p2, int(wager))
    testDraw(p1)
    testDraw(p2)
    testResolved
    expectDisputeResolved(p1, p2)
  {
    engine.resolveDispute(gameId, GameOutcome.Draw);
  }
}
