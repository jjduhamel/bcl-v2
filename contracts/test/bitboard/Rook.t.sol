// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import './Bitboard.t.sol';

abstract contract RookTest is BitboardTest {
  using Bitboard for Bitboard.Bitboard;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testMovesOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);
    for (uint8 _r=0; _r<8; _r++) {
      if (_r == r) continue;
      uint8 to = _r*8+f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      _testLegalMove(c, Piece.Rook, from, to);
    }
  }

  function testMovesOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);
    for (uint8 _f=0; _f<8; _f++) {
      if (_f == f) continue;
      uint8 to = r*8+_f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      _testLegalMove(c, Piece.Rook, from, to);
    }
  }

  function testIllegalMoves(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);
    for (uint8 _r=0; _r<8; _r++) {
      if (_r == r) continue;
      for (uint8 _f=0; _f<8; _f++) {
        if (_f == f) continue;
        uint8 to = _r*8+_f;
        clearBitboard();
        b.place(c, Piece.Rook, from);
        _testIllegalMove(c, Piece.Rook, from, to);
      }
    }
  }

  function testRookCantJumpOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);

    // Scan up-until
    for (uint8 _r=1; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);

    // Scan up-until
    for (uint8 _f=1; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpSelfOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);

    // Scan up-until
    for (uint8 _r=1; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpSelfOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard.rank(from);
    uint8 f = Bitboard.file(from);

    // Scan up-until
    for (uint8 _f=1; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      clearBitboard();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }
}

contract WhiteRookTest is RookTest {
  constructor() RookTest(Color.White) {}
}

contract BlackRookTest is RookTest {
  constructor() RookTest(Color.Black) {}
}
