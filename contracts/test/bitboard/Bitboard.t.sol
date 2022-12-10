// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@oz/utils/Strings.sol';
import '@lib/Bitboard.sol';

using Bitboard for Bitboard.Bitboard;

contract BitboardWrapper {
  Bitboard.Bitboard internal b;

  constructor() {
    initialize();
  }

  function initialize() public {
    b.initialize();
  }

  function initialize(Color c, Piece p, uint64 bb) public {
    return b.initialize(c, p, bb);
  }

  function initialize(Color c, Piece p, uint8 r, uint8 bb) public {
    b.initialize(c, p, uint64(bb) << (8 * r));
  }

  function place(Color c, Piece p, uint8 i) public {
    b.place(c, p, i);
  }

  function move(Color c, Piece p, uint8 from, uint8 to) public {
    b.move(c, p, from, to);
  }

  function bitboard(Color c, Piece p) public view returns (bytes8) {
    return b.bitboard(c, p);
  }

  function bitboard(Color c) public view returns (bytes8) {
    return b.bitboard(c);
  }

  function bitboard() public view returns (bytes8) {
    return b.bitboard();
  }
}

abstract contract BitboardTest is Test {
  BitboardWrapper internal b;

  constructor() {
    b = new BitboardWrapper();
  }

  function setUp() virtual public {
    clearBitboard();
  }

  function printBitboard(bytes8 bb1, bytes8 bb2, bytes8 bb3) internal {
    console.log('     +-----------------+');
    for (uint r=0; r<8; r++) {
      uint _r = 7-r;
      string memory s = string.concat(Strings.toHexString(_r*8), ' |');
      for (uint f=0; f<8; f++) {
        if (uint8(bb1[_r]) & 1<<f > 0) {
          s = string.concat(s, ' 1');
        } else if (uint8(bb2[_r]) & 1<<f > 0) {
          s = string.concat(s, ' 2');
        } else if (uint8(bb3[_r]) & 1<<f > 0) {
          s = string.concat(s, ' 3');
        } else {
          s = string.concat(s, ' -');
        }
      }
      s = string.concat(s, ' |');
      console.log(s);
    }
    console.log('     +-----------------+');
    console.log('       A B C D E F G H');
  }

  function printBitboard(bytes8 bb1, bytes8 bb2) internal {
    printBitboard(bb1, bb2, bytes8(0));
  }

  function printBitboard(bytes8 bb) internal {
    printBitboard(bb, bytes8(0));
  }

  function printBitboard(Color c, Piece p) internal {
    printBitboard(b.bitboard(c, p), b.bitboard());
  }

  function printBitboard(Color c, Piece p, uint8 dest) internal {
    printBitboard(b.bitboard(c, p), b.bitboard(), Bitboard.mask(dest));
  }

  function printBitboard() internal {
    printBitboard(b.bitboard());
  }

  function clearBitboard() internal {
    // Place white pieces
    b.initialize(Color.White, Piece.Pawn, 1, 0x00);
    b.initialize(Color.White, Piece.Rook, 0x00);
    b.initialize(Color.White, Piece.Knight, 0x00);
    b.initialize(Color.White, Piece.Bishop, 0x00);
    b.initialize(Color.White, Piece.Queen, 0x00);
    b.initialize(Color.White, Piece.King, 0x00);
    // Place black pieces
    b.initialize(Color.Black, Piece.Pawn, 0x00);
    b.initialize(Color.Black, Piece.Rook, 0x00);
    b.initialize(Color.Black, Piece.Knight, 0x00);
    b.initialize(Color.Black, Piece.Bishop, 0x00);
    b.initialize(Color.Black, Piece.Queen, 0x00);
    b.initialize(Color.Black, Piece.King, 0x00);
  }

  /*
  function testInitialBoard() public {
    b.initialize();
    assertEq(b.bitboard(Color.White, Piece.Pawn)
           , bytes8(uint64(0xFF00)));
    assertEq(b.bitboard(Color.White, Piece.Rook)
           , bytes8(uint64(0x81)));
    assertEq(b.bitboard(Color.White, Piece.Knight)
           , bytes8(uint64(0x42)));
    assertEq(b.bitboard(Color.White, Piece.Bishop)
           , bytes8(uint64(0x24)));
    assertEq(b.bitboard(Color.White, Piece.Queen)
           , bytes8(uint64(0x08)));
    assertEq(b.bitboard(Color.White, Piece.King)
           , bytes8(uint64(0x10)));

    assertEq(b.bitboard(Color.Black, Piece.Pawn)
           , bytes8(uint64(0xFF) << (8*6)));
    assertEq(b.bitboard(Color.Black, Piece.Rook)
           , bytes8(uint64(0x81) << (8*7)));
    assertEq(b.bitboard(Color.Black, Piece.Knight)
           , bytes8(uint64(0x42) << (8*7)));
    assertEq(b.bitboard(Color.Black, Piece.Bishop)
           , bytes8(uint64(0x24) << (8*7)));
    assertEq(b.bitboard(Color.Black, Piece.Queen)
           , bytes8(uint64(0x08) << (8*7)));
    assertEq(b.bitboard(Color.Black, Piece.King)
           , bytes8(uint64(0x10) << (8*7)));
  }
  */

  function _testLegalMove(Color c, Piece p, uint8 from, uint8 to) public {
    b.move(c, p, from, to);
    // TODO
  }

  function _testIllegalMove(Color c, Piece p, uint8 from, uint8 to) public {
    vm.expectRevert('InvalidMove');
    b.move(c, p, from, to);
  }
}
