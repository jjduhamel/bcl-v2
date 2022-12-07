// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import './ChessGame.t.sol';

contract ResignGameTest is ChessGameTest {
  function setUp() public {
    engine.acceptChallenge{ value: deposit }(gameId);
  }

  function testResignAsWhite() public
    testBalanceDelta(p1, 0)
    testBalanceDelta(p2, int(2*wager))
    testOutcome(GameOutcome.BlackWon)
    testWinner(p2)
    testLoser(p1)
  {
    changePrank(p1);
    engine.resign(gameId);
  }

  function testResignAsBlack() public
    testBalanceDelta(p1, int(2*wager))
    testBalanceDelta(p2, 0)
    testOutcome(GameOutcome.WhiteWon)
    testWinner(p1)
    testLoser(p2)
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
