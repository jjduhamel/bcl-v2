// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

abstract contract QueenTest is BitboardTest {
  using SignedMathI8 for int8;
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  function testQueenMoves(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
      b.initialize(c, Piece.Queen, uint64(1)<<from);
      if (dr.abs() ==  df.abs() && dr != 0) {
        _testLegalMove(c, Piece.Queen, from, to);
      } else if (dr == 0 && df.abs() > 0) {
        _testLegalMove(c, Piece.Queen, from, to);
      } else if (df == 0 && dr.abs() > 0) {
        _testLegalMove(c, Piece.Queen, from, to);
      } else {
        _testIllegalMove(c, Piece.Queen, from, to);
      }
    }
  }

  function testQueenCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.place(c, Piece.Queen, from);
    _testIllegalMove(c, Piece.Queen, from, from);
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
      } else if (dr == 0 && df.abs() > 0) {
        _testIllegalMove(c, Piece.Queen, from, to);
      } else if (df == 0 && dr.abs() > 0) {
        _testIllegalMove(c, Piece.Queen, from, to);
      }
    }
  }

  function testQueenCaptures(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr != 0 || df != 0 || dr.abs() != df.abs()) continue;
      if (dr == 0 && df == 0) continue;
      b.initialize(c, Piece.Queen, uint64(1)<<from);
      b.initialize(o, Piece.Pawn, uint64(1) << to);
      _testLegalMove(c, Piece.Queen, from, to);
    }
  }

  function testQueenCantJumpOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _r=1; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(o, Piece.Pawn, l);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }
  }

  function testQueenCantJumpOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _f=1; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(o, Piece.Pawn, i);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }
  }

  function testQueenCantJumpSelfOnRank(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _r=0; _r<r; _r++) {
      uint8 l = _r*8+f;
      uint8 to = f;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }

    // Scan beyond
    for (uint8 _r=r+1; _r<=7; _r++) {
      uint8 l = _r*8+f;
      uint8 to = 0x38+f;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(c, Piece.Pawn, l);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }
  }

  function testQueenCantJumpSelfOnFile(uint8 from) public {
    vm.assume(from < 0x40);
    uint8 r = Bitboard._rank(from);
    uint8 f = Bitboard._file(from);

    // Scan up-until
    for (uint8 _f=0; _f<f; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(c, Piece.Pawn, i);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }

    // Scan beyond
    for (uint8 _f=f+1; _f<=7; _f++) {
      uint8 i = r*8+_f;
      uint8 to = r*8+7;
      b.clear();
      b.place(c, Piece.Queen, from);
      b.place(c, Piece.Pawn, i);
      printBitboard(c, Piece.Queen, to);
      _testIllegalMove(c, Piece.Queen, from, to);
    }
  }

  function testQueenCantJumpOnDiagonals(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 || dr.abs() != df.abs()) continue;
      for (int8 _dx=1; _dx < int8(dr.abs()); _dx++) {
        int8 _di = (dr > 0 ? _dx : -_dx)*8;
        _di += (df > 0 ? _dx : -_dx);
        b.initialize(c, Piece.Queen, uint64(1)<<from);
        b.initialize(o, Piece.Pawn, uint64(1) << uint8(int8(from)+_di));
        console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
        printBitboard(b.bitboard(c, Piece.Queen), b.bitboard(), Bitboard._mask(to));
        _testIllegalMove(c, Piece.Queen, from, to);
      }
    }
  }

  function testQueenCantJumpSelfOnDiagonals(uint8 from) public {
    vm.assume(from < 0x40);
    for (uint8 to=0; to<0x40; to++) {
      int8 dr = Bitboard._dr(from, to);
      int8 df = Bitboard._df(from, to);
      if (dr == 0 || dr.abs() != df.abs()) continue;
      for (int8 _dx=1; _dx <= int8(dr.abs()); _dx++) {
        int8 _di = (dr > 0 ? _dx : -_dx)*8;
        _di += (df > 0 ? _dx : -_dx);
        b.initialize(c, Piece.Queen, uint64(1)<<from);
        b.initialize(c, Piece.Pawn, uint64(1) << uint8(int8(from)+_di));
        console.log(Strings.toHexString(from), '->', Strings.toHexString(to));
        printBitboard(b.bitboard(c, Piece.Queen), b.bitboard(), Bitboard._mask(to));
        _testIllegalMove(c, Piece.Queen, from, to);
      }
    }
  }
}

contract WhiteQueenTest is QueenTest {
  constructor() QueenTest(Color.White) {}
}

contract BlackQueenTest is QueenTest {
  constructor() QueenTest(Color.Black) {}
}
