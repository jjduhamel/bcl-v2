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

  function pluck(Color c, Piece p, uint8 i) public {
    b.pluck(c, p, i);
  }

  function move(Color c, uint8 from, uint8 to) public returns (Piece) {
    return b.move(c, from, to);
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

  function captures(Color c) public view returns (Piece[] memory) {
    return b.captures(c);
  }

  function lookup(Color c, uint8 i) public view returns (Piece) {
    return b.lookup(c, i);
  }

  function disableCastling() public {
    b.__allowKingSideCastle = false;
    b.__allowQueenSideCastle = false;
  }

  function clear() public {
    b.initialize(Color.White, Piece.Pawn, uint64(0x00));
    b.initialize(Color.White, Piece.Rook, uint64(0x00));
    b.initialize(Color.White, Piece.Knight, uint64(0x00));
    b.initialize(Color.White, Piece.Bishop, uint64(0x00));
    b.initialize(Color.White, Piece.Queen, uint64(0x00));
    b.initialize(Color.White, Piece.King, uint64(0x00));
    b.initialize(Color.Black, Piece.Pawn, uint64(0x00));
    b.initialize(Color.Black, Piece.Rook, uint64(0x00));
    b.initialize(Color.Black, Piece.Knight, uint64(0x00));
    b.initialize(Color.Black, Piece.Bishop, uint64(0x00));
    b.initialize(Color.Black, Piece.Queen, uint64(0x00));
    b.initialize(Color.Black, Piece.King, uint64(0x00));
  }
}

abstract contract BitboardTest is Test {
  BitboardWrapper internal b;

  constructor() {
    b = new BitboardWrapper();
  }

  function setUp() virtual public {
    b.clear();
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
    printBitboard(b.bitboard(c, p), b.bitboard(), Bitboard._mask(dest));
  }

  function printBitboard() internal {
    printBitboard(b.bitboard());
  }

  function _testLegalMove(Color c, Piece p, uint8 from, uint8 to) public {
    Color o = Color(1-uint(c));
    Piece pd = b.lookup(o, to);
    bytes8 bbo = b.bitboard(o, pd);
    Piece po = b.move(c, from, to);
    assertTrue(pd == po);
    if (pd != Piece.Empty) {
      assertTrue(b.bitboard(o, po) != bbo);
    } else {
      assertTrue(b.bitboard(o, po) == bbo);
    }
  }

  function _testIllegalMove(Color c, Piece p, uint8 from, uint8 to) public {
    vm.expectRevert('InvalidMove');
    b.move(c, from, to);
  }

  modifier expectCapture(Color o, Piece p) {
    Color c = Color(1-uint(o));
    Piece[] memory start = b.captures(c);
    _;
    Piece[] memory end = b.captures(c);
    console.log(start.length, end.length);
    assertTrue(end.length > start.length);
    for (uint j=start.length; j<end.length; j++) {
      //assertTrue(end[j] == p);
    }
  }
}
