// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@lib/UCI.sol';
import '@lib/Bitboard.sol';

contract UCITest is Test {
  function testParseMove() public {
    (uint8 from, uint8 to, Piece promotion) = UCI.parse('e2e4');
    assertEq(Bitboard._rank(from), 0x01);  // rank 2
    assertEq(Bitboard._file(from), 0x04);  // file e
    assertEq(Bitboard._rank(to),   0x03);  // rank 4
    assertEq(Bitboard._file(to),   0x04);  // file e
    assertTrue(promotion == Piece.Empty);
  }

  function testParseA1H8() public {
    (uint8 from, uint8 to,) = UCI.parse('a1h8');
    assertEq(Bitboard._rank(from), 0x00);  // rank 1
    assertEq(Bitboard._file(from), 0x00);  // file a
    assertEq(Bitboard._rank(to),   0x07);  // rank 8
    assertEq(Bitboard._file(to),   0x07);  // file h
  }

  function testParsePromotionQueen() public {
    (,, Piece p) = UCI.parse('a7a8q');
    assertTrue(p == Piece.Queen);
  }

  function testParsePromotionRook() public {
    (,, Piece p) = UCI.parse('a7a8r');
    assertTrue(p == Piece.Rook);
  }

  function testParsePromotionBishop() public {
    (,, Piece p) = UCI.parse('a7a8b');
    assertTrue(p == Piece.Bishop);
  }

  function testParsePromotionKnight() public {
    (,, Piece p) = UCI.parse('a7a8n');
    assertTrue(p == Piece.Knight);
  }

  function testRejectsTooShort() public {
    vm.expectRevert('InvalidMove');
    UCI.parse('a2a');
  }

  function testRejectsTooLong() public {
    vm.expectRevert('InvalidMove');
    UCI.parse('a2a3bb');
  }

  function testRejectsEmpty() public {
    vm.expectRevert('InvalidMove');
    UCI.parse('');
  }

  function testRejectsInvalidPromotionChar() public {
    vm.expectRevert('InvalidPromotion');
    UCI.parse('a7a8x');
  }

  function testRejectsInvalidFile() public {
    vm.expectRevert('InvalidMove');
    UCI.parse('i2e4');
  }

  function testRejectsInvalidRank() public {
    vm.expectRevert('InvalidMove');
    UCI.parse('a9e4');
  }
}
