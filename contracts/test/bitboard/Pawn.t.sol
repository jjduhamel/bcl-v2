// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@lib/SignedMathI8.sol';
import './Bitboard.t.sol';

contract PawnTest is BitboardTest {
  using SignedMathI8 for int8;

  function setUp() override public {
    b.initialize();
  }

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

  function testWhiteMoves(uint8 from) public {
    vm.assume(from < 64);
    clearBitboard();
    b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard.rank(from);
    for (uint8 to=0; to<64; to++) {
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (r == 1 && to == from+0x10) {
        _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else if (to == from+0x08) {
        _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.White, Piece.Pawn, from, to);
      }
    }
  }

  function testBlackMoves(uint8 from) public {
    vm.assume(from < 64);
    clearBitboard();
    b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard.rank(from);
    for (uint8 to=0; to<64; to++) {
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (r == 6 && from == to+0x10) {
        _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else if (from == to+0x08) {
        _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.Black, Piece.Pawn, from, to);
      }
    }
  }

  function testWhiteCaptures(uint8 from) public {
    vm.assume(from < 64);
    clearBitboard();
    b.initialize(Color.Black, Piece.Pawn, uint64(0xFFFFFFFFFFFFFFFF));
    b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard.rank(from);
    for (uint8 to=0; to<64; to++) {
      int8 _dr = Bitboard._dr(from, to);
      int8 _df = Bitboard._df(from, to);
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (_dr == 1 && _df.abs() == 1) {
        _testLegalMove(Color.White, Piece.Pawn, from, to);
        b.initialize(Color.White, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.White, Piece.Pawn, from, to);
      }
    }
  }

  function testBlackCaptures(uint8 from) public {
    vm.assume(from < 64);
    clearBitboard();
    b.initialize(Color.White, Piece.Pawn, uint64(0xFFFFFFFFFFFFFFFF));
    b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
    uint r = Bitboard.rank(from);
    for (uint8 to=0; to<64; to++) {
      int8 _dr = Bitboard._dr(from, to);
      int8 _df = Bitboard._df(from, to);
      console.log(r, Strings.toHexString(from), '->', Strings.toHexString(to));
      if (_dr == -1 && _df.abs() == 1) {
        _testLegalMove(Color.Black, Piece.Pawn, from, to);
        b.initialize(Color.Black, Piece.Pawn, uint64(1)<<from);
      } else {
        _testIllegalMove(Color.Black, Piece.Pawn, from, to);
      }
    }
  }

  /*
   * Corner-cases
   */

  // Test that players can't overflow the squares and wrap around
  // to the other side of the board.  
  function testPlus7Overflow() public {
    clearBitboard();
    b.place(Color.White, Piece.Pawn, 0x08);
    b.place(Color.Black, Piece.Pawn, 0x0F);
    _testIllegalMove(Color.White, Piece.Pawn, 0x08, 0x0F);
  }

  function testPlus9Overflow() public {
    clearBitboard();
    b.place(Color.White, Piece.Pawn, 0x0F);
    b.place(Color.Black, Piece.Pawn, 0x18);
    _testIllegalMove(Color.White, Piece.Pawn, 0x0F, 0x18);
  }
}
