// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

abstract contract RookTest is BitboardTest {
  using SignedMathI8 for int8;
  using Bitboard for Bitboard.Bitboard;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testMovesOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);
    for (uint8 _r=0; _r<8; _r++) {
      if (_r == r) continue;
      uint8 to = _r*8+f;
      b.clear();
      b.place(c, Piece.Rook, from);
      _testLegalMove(c, Piece.Rook, from, to);
    }
  }

  function testMovesOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);
    for (uint8 _f=0; _f<8; _f++) {
      if (_f == f) continue;
      uint8 to = r*8+_f;
      b.clear();
      b.place(c, Piece.Rook, from);
      _testLegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.place(c, Piece.Rook, from);
    _testIllegalMove(c, Piece.Rook, from, from);
  }

  function testRookCantMoveToOccupiedSquare(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      b.initialize(c, Piece.Rook, uint64(1)<<from);
      b.initialize(c, Piece.Pawn, uint64(1) << to);
      if (dr == 0 && df.abs() > 0) {
        _testIllegalMove(c, Piece.Rook, from, to);
      } else if (df == 0 && dr.abs() > 0) {
        _testIllegalMove(c, Piece.Rook, from, to);
      }
    }
  }

  function testIllegalMoves(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);
    for (uint8 _r=0; _r<8; _r++) {
      if (_r == r) continue;
      for (uint8 _f=0; _f<8; _f++) {
        if (_f == f) continue;
        uint8 to = _r*8+_f;
        b.clear();
        b.place(c, Piece.Rook, from);
        _testIllegalMove(c, Piece.Rook, from, to);
      }
    }
  }

  function testRookCantJumpOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _r=1; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _f=1; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpSelfOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _r=0; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<=7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }
  }

  function testRookCantJumpSelfOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _f=0; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      b.clear();
      b.place(c, Piece.Rook, from);
      b.place(c, Piece.Pawn, i);
      printBitboard(c, Piece.Rook, to);
      _testIllegalMove(c, Piece.Rook, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<=7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      b.clear();
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
