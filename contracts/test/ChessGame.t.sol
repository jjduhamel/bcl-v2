// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/Lobby.sol';
import '@src/ChessEngine.sol';
import './Challenge.t.sol';

abstract contract ChessGameTest is ChallengeTest {
  constructor() {
    changePrank(p1);
    lobby.challenge{ value: deposit }(p2, true, timePerMove, wager);
    uint[] memory challenges = lobby.challenges(p1);
    gameId = challenges[0];
    changePrank(p2);
  }

  function _move(address player, string memory san) internal {
    changePrank(player);
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
