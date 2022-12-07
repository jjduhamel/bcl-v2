// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@src/Bitboard.sol';
import './Lobby.t.sol';

contract BitboardTest is Test {
  using Bitboard for Bitboard.Bitboard;
  Bitboard.Bitboard b;

  function setUp() public {
    console.log('Initialize bitboard');
    b.initialize();
  }

  function testInitialBoard() public {
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.Pawn)
           , bytes8(uint64(0xFF00)));
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.Rook)
           , bytes8(uint64(0x81)));
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.Knight)
           , bytes8(uint64(0x42)));
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.Bishop)
           , bytes8(uint64(0x24)));
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.Queen)
           , bytes8(uint64(0x08)));
    assertEq(b.bitboard(Bitboard.Color.White, Bitboard.Piece.King)
           , bytes8(uint64(0x10)));

    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.Pawn)
           , bytes8(uint64(0xFF) << (8*6)));
    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.Rook)
           , bytes8(uint64(0x81) << (8*7)));
    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.Knight)
           , bytes8(uint64(0x42) << (8*7)));
    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.Bishop)
           , bytes8(uint64(0x24) << (8*7)));
    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.Queen)
           , bytes8(uint64(0x08) << (8*7)));
    assertEq(b.bitboard(Bitboard.Color.Black, Bitboard.Piece.King)
           , bytes8(uint64(0x10) << (8*7)));
  }

  function testLegalMove() public {
    b.move(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x08, 0x10);
  }

  function testInvalidOrigin() public {
    vm.expectRevert('InvalidOrigin');
    b.move(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x10, 0x18);
  }

  function testInvalidDesitation() public {
    vm.expectRevert('InvalidDestination');
    b.move(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x08, 0x08);
  }

  function _testLegalMove(Bitboard.Color c, Bitboard.Piece p, uint8 from, uint8 to) public {
    b.move(Bitboard.Color.White, Bitboard.Piece.Pawn, from, to);
    // TODO
  }

  function _testIllegalMove(Bitboard.Color c, Bitboard.Piece p, uint8 from, uint8 to) public {
    vm.expectRevert('InvalidMove');
    b.move(Bitboard.Color.White, Bitboard.Piece.Pawn, from, to);
  }

  function testPawnMoves() public {
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x08, 0x18);
    //_testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x18, 0x20);
    //_testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x20, 0x28);
    //_testIllegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x28, 0x30);
    //bytes8 p = bytes8(b.bitboard(Bitboard.Color.Black));
    //bytes8 p = bytes8(b.bitboard(Bitboard.Color.White));
    //bytes8 p = bytes8(b.bitboard());
    /*
    for (uint r=0; r<p.length; r++) {
      console.log(uint8(p[r]));
    }
    */
  }

  function testPawnCaptures() public {
    b.initialize(Bitboard.Color.Black, Bitboard.Piece.Pawn, 2, 0xFF);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x08, 0x11);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x09, 0x12);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0A, 0x13);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0B, 0x14);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0C, 0x15);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0D, 0x16);
    _testLegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0E, 0x17);
    _testIllegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0F, 0x18);
  }

  // Test that players can't overflow the squares and wrap around
  // to the other side of the board.
  function testLeftOverflowPawn() public {
    b.initialize(Bitboard.Color.White, Bitboard.Piece.Pawn, 1, 0x01);
    b.initialize(Bitboard.Color.Black, Bitboard.Piece.Pawn, 1, 0x80);
    _testIllegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x08, 0x0F);
  }

  function testRightOverflowPawn() public {
    b.initialize(Bitboard.Color.Black, Bitboard.Piece.Pawn, 3, 0xFF);
    _testIllegalMove(Bitboard.Color.White, Bitboard.Piece.Pawn, 0x0F, 0x18);
  }
}
