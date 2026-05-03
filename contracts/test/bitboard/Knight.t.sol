// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

abstract contract KnightTest is BitboardTest {
  using SignedMathI8 for int8;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testMoves(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
      b.initialize(c, Piece.Knight, uint64(1)<<from);
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr.abs() == 1 && df.abs() == 2) {
        _testLegalMove(c, Piece.Knight, from, to);
      } else if (dr.abs() == 2 && df.abs() == 1) {
        _testLegalMove(c, Piece.Knight, from, to);
      } else {
        _testIllegalMove(c, Piece.Knight, from, to);
      }
    }
  }

  function testKnightCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.place(c, Piece.Knight, from);
    _testIllegalMove(c, Piece.Knight, from, from);
  }

  function testKnightCantMoveToOccupiedSquare(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      b.initialize(c, Piece.Knight, uint64(1)<<from);
      b.initialize(c, Piece.Pawn, uint64(1)<<to);
      if (dr.abs() == 1 && df.abs() == 2) {
        _testIllegalMove(c, Piece.Knight, from, to);
      } else if (dr.abs() == 2 && df.abs() == 1) {
        _testIllegalMove(c, Piece.Knight, from, to);
      }
    }
  }

  function testKnightCaptures(uint8 from) public
    expectCapture(o, Piece.Pawn)
  {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      b.initialize(c, Piece.Knight, uint64(1)<<from);
      b.initialize(o, Piece.Pawn, uint64(1)<<to);
      if (dr.abs() == 1 && df.abs() == 2) {
        _testLegalMove(c, Piece.Knight, from, to);
      } else if (dr.abs() == 2 && df.abs() == 1) {
        _testLegalMove(c, Piece.Knight, from, to);
      }
    }
  }
}

contract WhiteKnightTest is KnightTest {
  constructor() KnightTest(Color.White) {}
}

contract BlackKnightTest is KnightTest {
  constructor() KnightTest(Color.Black) {}
}
