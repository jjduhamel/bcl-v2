// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

abstract contract BishopTest is BitboardTest {
  using SignedMathI8 for int8;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testBishopMoves(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
      b.initialize(c, Piece.Bishop, uint64(1)<<from);
      if (dr.abs() ==  df.abs() && dr != 0) {
        _testLegalMove(c, Piece.Bishop, from, to);
      } else {
        _testIllegalMove(c, Piece.Bishop, from, to);
      }
    }
  }

  function testBishopCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.place(c, Piece.Bishop, from);
    _testIllegalMove(c, Piece.Bishop, from, from);
  }

  function testQueenCantMoveToOccupiedSquare(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      b.initialize(c, Piece.Queen, uint64(1)<<from);
      b.initialize(c, Piece.Pawn, uint64(1) << to);
      if (dr.abs() ==  df.abs() && dr != 0) {
        _testIllegalMove(c, Piece.Queen, from, to);
      }
    }
  }

  function testBishopCaptures(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 || dr.abs() != df.abs()) continue;
      b.initialize(c, Piece.Bishop, uint64(1)<<from);
      b.initialize(o, Piece.Pawn, uint64(1) << to);
      _testLegalMove(c, Piece.Bishop, from, to);
    }
  }

  function testBishopCantJumpOver(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 || dr.abs() != df.abs()) continue;
      for (int8 _dx=1; _dx < int8(dr.abs()); _dx++) {
        int8 _di = (dr > 0 ? _dx : -_dx)*8;
        _di += (df > 0 ? _dx : -_dx);
        b.initialize(c, Piece.Bishop, uint64(1)<<from);
        b.initialize(o, Piece.Pawn, uint64(1) << uint8(int8(from)+_di));
        console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
        printBitboard(b.bitboard(c, Piece.Bishop), b.bitboard(), Bitboard._mask(to));
        _testIllegalMove(c, Piece.Bishop, from, to);
      }
    }
  }

  function testBishopCantJumpOverSelf(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 || dr.abs() != df.abs()) continue;
      for (int8 _dx=1; _dx <= int8(dr.abs()); _dx++) {
        int8 _di = (dr > 0 ? _dx : -_dx)*8;
        _di += (df > 0 ? _dx : -_dx);
        b.initialize(c, Piece.Bishop, uint64(1)<<from);
        b.initialize(c, Piece.Pawn, uint64(1) << uint8(int8(from)+_di));
        console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
        printBitboard(b.bitboard(c, Piece.Bishop), b.bitboard(), Bitboard._mask(to));
        _testIllegalMove(c, Piece.Bishop, from, to);
      }
    }
  }
}

contract WhiteBishopTest is BishopTest {
  constructor() BishopTest(Color.White) {}
}

contract BlackBishopTest is BishopTest {
  constructor() BishopTest(Color.Black) {}
}
