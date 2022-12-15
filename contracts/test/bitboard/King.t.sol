// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

abstract contract KingTest is BitboardTest {
  using SignedMathI8 for int8;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testKingMoves(uint8 from) public {
    vm.assume(from < 0x40);
    b.disableCastling();
    uint nLegalMoves = 0;
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
      b.initialize(c, Piece.King, uint64(1)<<from);
      if (dr == 0 && df == 0) continue;
      if (dr.abs() <=  1 && df.abs() <= 1) {
        nLegalMoves++;
        _testLegalMove(c, Piece.King, from, to);
      } else {
        _testIllegalMove(c, Piece.King, from, to);
      }
      console.log(nLegalMoves);
      assertTrue(nLegalMoves <= 8);
    }
  }

  function testKingCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.place(c, Piece.King, from);
    _testIllegalMove(c, Piece.King, from, from);
  }

  function testKingCaptures(uint8 from) public
    expectCapture(o, Piece.Pawn)
  {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 && df == 0) continue;
      if (dr.abs() <=  1 && df.abs() <= 1) {
        b.initialize(c, Piece.King, uint64(1)<<from);
        b.initialize(o, Piece.Pawn, uint64(1) << to);
        _testLegalMove(c, Piece.King, from, to);
      }
    }
  }

  function testKingCantMoveToOccupiedSquare(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr.abs() == 1 || df.abs() == 1) {
        b.initialize(c, Piece.King, uint64(1)<<from);
        b.initialize(c, Piece.Pawn, uint64(1) << to);
        _testIllegalMove(c, Piece.King, from, to);
      }
    }
  }

  function testKingSideCastle() public {
    b.initialize();
    if (c == Color.White) {
      _testIllegalMove(c, Piece.King, 0x04, 0x06);
      b.pluck(c, Piece.Bishop, 0x05);
      _testIllegalMove(c, Piece.King, 0x04, 0x06);
      b.pluck(c, Piece.Knight, 0x06);
      _testLegalMove(c, Piece.King, 0x04, 0x06);
    } else {
      _testIllegalMove(c, Piece.King, 0x3C, 0x3E);
      b.pluck(c, Piece.Bishop, 0x3D);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3E);
      b.pluck(c, Piece.Knight, 0x3E);
      _testLegalMove(c, Piece.King, 0x3C, 0x3E);
    }
    //printBitboard(b.bitboard(c, Piece.King), b.bitboard(c, Piece.Rook), b.bitboard());
  }

  function testKingSideCastleFailsAfterRookMoves() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Bishop, 0x05);
      b.pluck(c, Piece.Knight, 0x06);
      _testLegalMove(c, Piece.Rook, 0x07, 0x06);
      _testLegalMove(c, Piece.Rook, 0x06, 0x07);
      _testIllegalMove(c, Piece.King, 0x04, 0x06);
    } else {
      b.pluck(c, Piece.Bishop, 0x3D);
      b.pluck(c, Piece.Knight, 0x3E);
      _testLegalMove(c, Piece.Rook, 0x3F, 0x3E);
      _testLegalMove(c, Piece.Rook, 0x3E, 0x3F);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3E);
    }
  }

  function testKingSideCastleFailsAfterKingMoves() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Bishop, 0x05);
      b.pluck(c, Piece.Knight, 0x06);
      _testLegalMove(c, Piece.King, 0x04, 0x05);
      _testLegalMove(c, Piece.King, 0x05, 0x04);
      _testIllegalMove(c, Piece.King, 0x04, 0x06);
    } else {
      b.pluck(c, Piece.Bishop, 0x3D);
      b.pluck(c, Piece.Knight, 0x3E);
      _testLegalMove(c, Piece.King, 0x3C, 0x3D);
      _testLegalMove(c, Piece.King, 0x3D, 0x3C);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3E);
    }
  }

  function testKingSideCastleCantJump() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Bishop, 0x05);
      b.pluck(c, Piece.Knight, 0x06);
      b.place(o, Piece.Pawn, 0x05);
      _testIllegalMove(c, Piece.King, 0x04, 0x06);
    } else {
      b.pluck(c, Piece.Bishop, 0x3D);
      b.pluck(c, Piece.Knight, 0x3E);
      b.place(o, Piece.Pawn, 0x3D);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3E);
    }
  }

  function testQueenSideCastle() public {
    b.initialize();
    if (c == Color.White) {
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
      b.pluck(c, Piece.Queen, 0x03);
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
      b.pluck(c, Piece.Bishop, 0x02);
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
      b.pluck(c, Piece.Knight, 0x01);
      _testLegalMove(c, Piece.King, 0x04, 0x02);
    } else {
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
      b.pluck(c, Piece.Queen, 0x03B);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
      b.pluck(c, Piece.Bishop, 0x3A);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
      b.pluck(c, Piece.Knight, 0x39);
      _testLegalMove(c, Piece.King, 0x3C, 0x3A);
    }
    //printBitboard(b.bitboard(c, Piece.King), b.bitboard(c, Piece.Rook), b.bitboard());
  }

  function testQueenSideCastleFailsAfterRookMoves() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Queen, 0x03);
      b.pluck(c, Piece.Bishop, 0x02);
      b.pluck(c, Piece.Knight, 0x01);
      _testLegalMove(c, Piece.Rook, 0x00, 0x01);
      _testLegalMove(c, Piece.Rook, 0x01, 0x00);
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
    } else {
      b.pluck(c, Piece.Queen, 0x03B);
      b.pluck(c, Piece.Bishop, 0x3A);
      b.pluck(c, Piece.Knight, 0x39);
      _testLegalMove(c, Piece.Rook, 0x38, 0x39);
      _testLegalMove(c, Piece.Rook, 0x39, 0x38);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
    }
  }

  function testQueenSideCastleFailsAfterKingMoves() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Queen, 0x03);
      b.pluck(c, Piece.Bishop, 0x02);
      b.pluck(c, Piece.Knight, 0x01);
      _testLegalMove(c, Piece.King, 0x04, 0x03);
      _testLegalMove(c, Piece.King, 0x03, 0x04);
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
    } else {
      b.pluck(c, Piece.Queen, 0x03B);
      b.pluck(c, Piece.Bishop, 0x3A);
      b.pluck(c, Piece.Knight, 0x39);
      _testLegalMove(c, Piece.King, 0x3C, 0x3B);
      _testLegalMove(c, Piece.King, 0x3B, 0x3C);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
    }
  }

  function testQueenSideCastleCantJump() public {
    b.initialize();
    if (c == Color.White) {
      b.pluck(c, Piece.Queen, 0x03);
      b.pluck(c, Piece.Bishop, 0x02);
      b.pluck(c, Piece.Knight, 0x01);
      b.place(o, Piece.Pawn, 0x03);
      _testIllegalMove(c, Piece.King, 0x04, 0x02);
    } else {
      b.pluck(c, Piece.Queen, 0x03B);
      b.pluck(c, Piece.Bishop, 0x3A);
      b.pluck(c, Piece.Knight, 0x39);
      b.place(o, Piece.Pawn, 0x3B);
      _testIllegalMove(c, Piece.King, 0x3C, 0x3A);
    }
  }
}

contract WhiteKingTest is KingTest {
  constructor() KingTest(Color.White) {}
}

contract BlackKingTest is KingTest {
  constructor() KingTest(Color.Black) {}
}
