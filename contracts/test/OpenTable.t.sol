// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import './Challenge.t.sol';
import { MockERC20 } from './ChessGameERC20.t.sol';

// Open tables: open() lists a challenge with no opponent in challenges(address(0));
// join() seats the joiner and hands the turn to the creator to accept/decline.
contract OpenTableTest is ChallengeTest {
  function setUp() public {
    changePrank(p1);
  }

  // p1 opens as white; returns the gameId
  function _open(uint w) internal returns (uint) {
    return lobby.createTable{ value: w }(p1, true, timePerMove, w, address(0));
  }

  function testOpenListsInGlobalRegistry() public {
    uint id = _open(0);
    IChessEngine.GameData memory g = engine.game(id);
    assertEq(g.whitePlayer, p1);
    assertEq(g.blackPlayer, address(0));
    assertTrue(g.state == IChessEngine.GameState.Pending);

    uint[] memory open = lobby.challenges(address(0));
    assertEq(open[open.length - 1], id);
    assertEq(lobby.challenges(p1)[0], id);
  }

  function testOpenEmitsNewChallenge() public {
    vm.expectEmit(false, true, true, true, address(lobby));
    emit NewChallenge(0, p1, address(0));
    _open(0);
  }

  function testMultipleOpenTablesJoinRemovesOnlyOne() public {
    uint id1 = _open(0);
    uint id2 = _open(0);
    assertEq(lobby.challenges(address(0)).length, 2);

    changePrank(p2);
    lobby.joinTable(id1, p2);

    uint[] memory open = lobby.challenges(address(0));
    assertEq(open.length, 1);
    assertEq(open[0], id2);
  }

  function testJoinSeatsOpponentAndFlipsTurn() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2); // p2 takes black

    IChessEngine.GameData memory g = engine.game(id);
    assertEq(g.whitePlayer, p1);
    assertEq(g.blackPlayer, p2);
    assertEq(g.currentMove, p1); // creator must accept
    assertTrue(g.state == IChessEngine.GameState.Pending);
  }

  function testJoinLeavesOpenRegistry() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);

    assertEq(lobby.challenges(address(0)).length, 0);
    assertEq(lobby.challenges(p2)[0], id);
  }

  // The joiner can't choose a colour — they always fill the creator's open seat,
  // so the creator keeps the colour they opened with.
  function testJoinerCannotFlipCreatorColor() public {
    uint id = _open(0); // p1 opened as white
    changePrank(p2);
    lobby.joinTable(id, p2);

    IChessEngine.GameData memory g = engine.game(id);
    assertEq(g.whitePlayer, p1);
    assertEq(g.blackPlayer, p2);
    assertEq(g.currentMove, p1);
  }

  // Opening as black leaves the white seat empty; the joiner fills it.
  function testOpenAsBlackThenJoinSeatsWhite() public {
    uint id = lobby.createTable(p1, false, timePerMove, 0, address(0));
    IChessEngine.GameData memory g = engine.game(id);
    assertEq(g.whitePlayer, address(0));
    assertEq(g.blackPlayer, p1);

    changePrank(p2);
    lobby.joinTable(id, p2); // p2 takes the empty white seat
    g = engine.game(id);
    assertEq(g.whitePlayer, p2);
    assertEq(g.blackPlayer, p1);
    assertEq(g.currentMove, p1);

    assertEq(lobby.challenges(address(0)).length, 0);
    assertEq(lobby.challenges(p2)[0], id);
  }

  function testCreatorAcceptsJoinedTable() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(p1);
    lobby.acceptChallenge(id);

    IChessEngine.GameData memory g = engine.game(id);
    assertTrue(g.state == IChessEngine.GameState.Started);
    assertEq(lobby.games(address(0))[0], id);
    assertEq(lobby.games(p1)[0], id);
    assertEq(lobby.games(p2)[0], id);
  }

  // A played-out open-table game leaves the global active feed and enters global history.
  function testFinishedOpenGameEntersGlobalHistory() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(p1);
    lobby.acceptChallenge(id);
    assertEq(lobby.games(address(0))[0], id);

    engine.resign(id); // white (p1) resigns -> BlackWon -> finishGame

    assertEq(lobby.games(address(0)).length, 0);
    assertEq(lobby.history(address(0))[0], id);
    assertEq(lobby.history(p1)[0], id);
    assertEq(lobby.history(p2)[0], id);
  }

  function testCreatorDeclinesJoinedTable() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(p1);
    lobby.declineChallenge(id);

    IChessEngine.GameData memory g = engine.game(id);
    assertTrue(g.state == IChessEngine.GameState.Declined);
    assertEq(lobby.challenges(p1).length, 0);
    assertEq(lobby.challenges(p2).length, 0);
  }

  function testWageredOpenJoinEscrowsBothThenChargesFees() public {
    uint id = _open(wager); // p1 escrows at open
    changePrank(p2);
    lobby.joinTable{ value: wager }(id, p2); // p2 escrows at join

    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(id, p1), wager);
    assertEq(lobby.checkPlayerDeposit(id, p2), wager);

    changePrank(p1);
    lobby.acceptChallenge(id);

    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(id, p1), wager - fee());
    assertEq(lobby.checkPlayerDeposit(id, p2), wager - fee());
  }

  // Same flow as the ETH case but with an ERC20 wager pulled via transferFrom.
  function testERC20OpenJoinEscrowsBothThenChargesFees() public {
    MockERC20 token = new MockERC20();
    token.mint(p1, 100 ether);
    token.mint(p2, 100 ether);

    changePrank(p1);
    token.approve(address(lobby), wager);
    uint id = lobby.createTable(p1, true, timePerMove, wager, address(token));

    changePrank(p2);
    token.approve(address(lobby), wager);
    lobby.joinTable(id, p2);

    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(id, p1), wager);
    assertEq(lobby.checkPlayerDeposit(id, p2), wager);

    changePrank(p1);
    lobby.acceptChallenge(id);

    changePrank(arbiter);
    assertEq(lobby.checkPlayerDeposit(id, p1), wager - fee());
    assertEq(lobby.checkPlayerDeposit(id, p2), wager - fee());
  }

  // A creator can't join their own table — they'd be playing themselves.
  function testCreatorJoinsOwnTableRejects() public {
    uint id = _open(0);
    vm.expectRevert();
    lobby.joinTable(id, p1);
  }

  // Nor can the creator seat one of their own agents — same owner on both sides.
  function testAgentJoinsOwnersTableRejects() public {
    address a1 = makeAddr('p1agent');
    changePrank(p1);
    lobby.registerAgent(a1, 'a1', '', '', '', '');
    uint id = _open(0);
    vm.expectRevert();
    lobby.joinTable(id, a1);
  }

  function testJoinNonOpenReverts() public {
    uint id = lobby.challenge(p1, p2, true, timePerMove, 0, address(0)); // named challenge
    changePrank(p3);
    vm.expectRevert();
    lobby.joinTable(id, p3);
  }

  // Once a table is joined both seats are filled; a second joiner is rejected by the engine.
  function testSecondJoinerRejected() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(p3);
    vm.expectRevert(Forbidden.selector);
    lobby.joinTable(id, p3);
  }

  // join resolves the seat owner via ownerOf, which rejects an unregistered address.
  function testUnregisteredCannotJoin() public {
    uint id = _open(0);
    address stranger = makeAddr('stranger');
    changePrank(stranger);
    vm.expectRevert(Unauthorized.selector);
    lobby.joinTable(id, stranger);
  }

  function testPreJoinCancelRefundsAndDeregisters() public {
    uint balBefore = p1.balance;
    uint id = _open(wager);
    assertEq(p1.balance, balBefore - wager);

    lobby.declineChallenge(id); // creator cancels an un-joined open table
    lobby.withdraw(address(0)); // pull the refund back to the wallet
    assertEq(p1.balance, balBefore);

    assertEq(lobby.challenges(address(0)).length, 0);
    assertEq(lobby.challenges(p1).length, 0);
  }

  // revokeTable: dedicated cancel path for open (un-joined) tables.
  function testRevokeRefundsAndDeregisters() public {
    uint balBefore = p1.balance;
    uint id = _open(wager);
    assertEq(p1.balance, balBefore - wager);

    lobby.closeTable(id);
    lobby.withdraw(address(0));
    assertEq(p1.balance, balBefore);

    assertEq(lobby.challenges(address(0)).length, 0);
    assertEq(lobby.challenges(p1).length, 0);
  }

  function testRevokeEmitsTableClosed() public {
    uint id = _open(0);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit TableClosed(0, p1);
    lobby.closeTable(id);
  }

  // join() removes the table from challenges(address(0)); the registry guard then closes revoke.
  function testRevokeAfterJoinReverts() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(p1);
    vm.expectRevert(Forbidden.selector);
    lobby.closeTable(id);
  }

  // A named challenge was never in challenges(address(0)).
  function testRevokeNamedChallengeReverts() public {
    uint id = lobby.challenge(p1, p2, true, timePerMove, 0, address(0));
    vm.expectRevert(Forbidden.selector);
    lobby.closeTable(id);
  }

  function testRevokeBySpectatorReverts() public {
    uint id = _open(0);
    changePrank(p3);
    vm.expectRevert(Unauthorized.selector);
    lobby.closeTable(id);
  }

  function testRevokeUnregisteredReverts() public {
    uint id = _open(0);
    address stranger = makeAddr('stranger');
    changePrank(stranger);
    vm.expectRevert(Unauthorized.selector);
    lobby.closeTable(id);
  }

  // closeTable: arbiter-elevated teardown of any open table. Refund still goes to the creator.
  function testCloseByArbiterRefundsCreator() public {
    uint balBefore = p1.balance;
    uint id = _open(wager);
    assertEq(p1.balance, balBefore - wager);

    changePrank(arbiter);
    lobby.closeTable(id);

    changePrank(p1);
    lobby.withdraw(address(0));
    assertEq(p1.balance, balBefore);

    assertEq(lobby.challenges(address(0)).length, 0);
    assertEq(lobby.challenges(p1).length, 0);

    IChessEngine.GameData memory g = engine.game(id);
    assertTrue(g.state == IChessEngine.GameState.Declined);
  }

  function testCloseEmitsTableClosed() public {
    uint id = _open(0);
    changePrank(arbiter);
    vm.expectEmit(false, true, true, true, address(lobby));
    emit TableClosed(0, p1);
    lobby.closeTable(id);
  }

  function testCloseByNonArbiterReverts() public {
    uint id = _open(0);
    changePrank(p2);
    vm.expectRevert(Unauthorized.selector);
    lobby.closeTable(id);
  }

  // Once joined, the table leaves challenges(address(0)) — the registry guard then closes close.
  function testCloseAfterJoinReverts() public {
    uint id = _open(0);
    changePrank(p2);
    lobby.joinTable(id, p2);
    changePrank(arbiter);
    vm.expectRevert(Forbidden.selector);
    lobby.closeTable(id);
  }

  function testCloseNamedChallengeReverts() public {
    uint id = lobby.challenge(p1, p2, true, timePerMove, 0, address(0));
    changePrank(arbiter);
    vm.expectRevert(Forbidden.selector);
    lobby.closeTable(id);
  }
}
