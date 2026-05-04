// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

contract PawnTest is BitboardTest {
  using SignedMathI8 for int8;

  function _tWP(uint8 f) internal {
    b.initialize();
    _testLegalMove(Color.White, Piece.Pawn, 0x08+f, 0x10+f);
    _testLegalMove(Color.White, Piece.Pawn, 0x10+f, 0x18+f);
    _testLegalMove(Color.White, Piece.Pawn, 0x18+f, 0x20+f);
    _testLegalMove(Color.White, Piece.Pawn, 0x20+f, 0x28+f);
    _testIllegalMove(Color.White, Piece.Pawn, 0x28+f, 0x30+f);
  }

  function _tBP(uint8 f) internal {
    b.initialize();
    _testLegalMove(Color.Black, Piece.Pawn, 0x30+f, 0x28+f);
    _testLegalMove(Color.Black, Piece.Pawn, 0x28+f, 0x20+f);
    _testLegalMove(Color.Black, Piece.Pawn, 0x20+f, 0x18+f);
    _testLegalMove(Color.Black, Piece.Pawn, 0x18+f, 0x10+f);
    _testIllegalMove(Color.Black, Piece.Pawn, 0x10+f, 0x08+f);
  }

  function testPawnMoves(uint8 f) public {
    vm.assume(f < 8);
    _tWP(f);
    _tBP(f);
  }

  function testWhitePawnCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.clear();
    b.place(Color.White, Piece.Pawn, from);
    _testIllegalMove(Color.White, Piece.Pawn, from, from);
  }

  function testBlackPawnCantMoveToOrigin(uint8 from) public {
    vm.assume(from < 0x40);
    b.clear();
    b.place(Color.Black, Piece.Pawn, from);
    _testIllegalMove(Color.Black, Piece.Pawn, from, from);
  }

  function testWhitePawnCantMoveToOccupiedSquare(uint8 f) public {
    vm.assume(f < 8);
    b.place(Color.White, Piece.Pawn, f+8);
    _testIllegalMove(Color.White, Piece.Pawn, f, f+8);
  }

  function testBlackPawnCantMoveToOccupiedSquare(uint8 f) public {
    vm.assume(f < 8);
    uint8 from = 0x30+f;
    b.place(Color.Black, Piece.Pawn, from-8);
    _testIllegalMove(Color.Black, Piece.Pawn, from, from-8);
  }

  function testWhiteMoves(uint8 from) public {
    vm.assume(from < 64);
    b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard._rank(from);
    for (uint8 to=0; to<64; to++) {
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (r == 1 && to == from+0x10) {
        _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else if (to == from+0x08) {
        if (r == 6) _testLegalMove(Color.White, Piece.Pawn, from, to, Piece.Queen);
        else _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.White, Piece.Pawn, from, to);
      }
    }
  }

  function testBlackMoves(uint8 from) public {
    vm.assume(from < 64);
    b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard._rank(from);
    for (uint8 to=0; to<64; to++) {
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (r == 6 && from == to+0x10) {
        _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else if (from == to+0x08) {
        if (r == 1) _testLegalMove(Color.Black, Piece.Pawn, from, to, Piece.Queen);
        else _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.Black, Piece.Pawn, from, to);
      }
    }
  }

  function testWhiteCaptures(uint8 from) public {
    vm.assume(from < 64);
    b.initialize(Color.Black, Piece.Pawn, uint64(0xFFFFFFFFFFFFFFFF));
    b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard._rank(from);
    for (uint8 to=0; to<64; to++) {
      int8 _dr = Bitboard._dr(from, to);
      int8 _df = Bitboard._df(from, to);
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (_dr == 1 && _df.abs() == 1) {
        if (Bitboard._rank(to) == 7) _testLegalMove(Color.White, Piece.Pawn, from, to, Piece.Queen);
        else _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.White, Piece.Pawn, from, to);
      }
    }
  }

  function testBlackCaptures(uint8 from) public {
    vm.assume(from < 64);
    b.initialize(Color.White, Piece.Pawn, uint64(0xFFFFFFFFFFFFFFFF));
    b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard._rank(from);
    for (uint8 to=0; to<64; to++) {
      int8 _dr = Bitboard._dr(from, to);
      int8 _df = Bitboard._df(from, to);
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (_dr == -1 && _df.abs() == 1) {
        if (Bitboard._rank(to) == 0) _testLegalMove(Color.Black, Piece.Pawn, from, to, Piece.Queen);
        else _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.Black, Piece.Pawn, from, to);
      }
    }
  }

  function testWhitePawnCantCaptureBackwards() public {
    b.place(Color.White, Piece.Pawn, 0x1C);  // e4
    b.place(Color.Black, Piece.Pawn, 0x13);  // d3 — backward diagonal
    _testIllegalMove(Color.White, Piece.Pawn, 0x1C, 0x13);
  }

  function testBlackPawnCantCaptureBackwards() public {
    b.place(Color.Black, Piece.Pawn, 0x24);  // e5
    b.place(Color.White, Piece.Pawn, 0x2D);  // f6 — backward diagonal
    _testIllegalMove(Color.Black, Piece.Pawn, 0x24, 0x2D);
  }

  /*
   * Corner-cases
   */

  function testWhiteBlockedHomerow(uint8 f) public {
    vm.assume(f < 8);
    b.initialize(Color.White, Piece.Pawn, 1, 0xFF);
    b.initialize(Color.Black, Piece.Pawn, 2, 0xFF);
    _testIllegalMove(Color.White, Piece.Pawn, 0x08+f, 0x18+f);
  }

  function testBlackBlockedHomerow(uint8 f) public {
    vm.assume(f < 8);
    b.initialize(Color.Black, Piece.Pawn, 6, 0xFF);
    b.initialize(Color.White, Piece.Pawn, 5, 0xFF);
    _testIllegalMove(Color.Black, Piece.Pawn, 0x30+f, 0x20+f);
  }

  // Test that players can't overflow the squares and wrap around
  // to the other side of the board.  
  function testPlus7Overflow() public {
    b.place(Color.White, Piece.Pawn, 0x08);
    b.place(Color.Black, Piece.Pawn, 0x0F);
    _testIllegalMove(Color.White, Piece.Pawn, 0x08, 0x0F);
  }

  function testPlus9Overflow() public {
    b.place(Color.White, Piece.Pawn, 0x0F);
    b.place(Color.Black, Piece.Pawn, 0x18);
    _testIllegalMove(Color.White, Piece.Pawn, 0x0F, 0x18);
  }

  function testPlus1Overflow() public {
    b.place(Color.White, Piece.Pawn, 0x0F);  // H2
    b.place(Color.Black, Piece.Pawn, 0x10);  // A3
    _testIllegalMove(Color.White, Piece.Pawn, 0x0F, 0x10);
  }

  function testMinus1Overflow() public {
    b.place(Color.Black, Piece.Pawn, 0x30);  // A7
    b.place(Color.White, Piece.Pawn, 0x2F);  // H6
    _testIllegalMove(Color.Black, Piece.Pawn, 0x30, 0x2F);
  }
}
