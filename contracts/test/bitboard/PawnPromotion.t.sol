// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import './Bitboard.t.sol';

abstract contract PawnPromotionTest is BitboardTest {
  Color c;
  Color o;

  constructor(Color color) {
    c = color;
    o = Color(1-uint(color));
  }

  // Start one row from promotion
  function _from(uint8 file) internal view returns (uint8) {
    return c == Color.White ? 0x30+file : 0x08+file;
  }

  // End on promotion row
  function _to(uint8 file) internal view returns (uint8) {
    return c == Color.White ? 0x38+file : file;
  }

  function _testPromotion(uint8 file, Piece p) internal {
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    b.move(c, _from(file), _to(file), p);
    assertEq(b.bitboard(c, Piece.Pawn), bytes8(0));
    assertEq(b.bitboard(c, p), bytes8(uint64(1) << _to(file)));
  }

  function testPromotesToQueen(uint8 file) public {
    vm.assume(file < 8);
    _testPromotion(file, Piece.Queen);
  }

  function testPromotesToRook(uint8 file) public {
    vm.assume(file < 8);
    _testPromotion(file, Piece.Rook);
  }

  function testPromotesToBishop(uint8 file) public {
    vm.assume(file < 8);
    _testPromotion(file, Piece.Bishop);
  }

  function testPromotesToKnight(uint8 file) public {
    vm.assume(file < 8);
    _testPromotion(file, Piece.Knight);
  }

  function testCantPromoteToPawn(uint8 file) public {
    vm.assume(file < 8);
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    vm.expectRevert('InvalidPromotion');
    b.move(c, _from(file), _to(file), Piece.Pawn);
  }

  function testCantPromoteToKing(uint8 file) public {
    vm.assume(file < 8);
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    vm.expectRevert('InvalidPromotion');
    b.move(c, _from(file), _to(file), Piece.King);
  }

  function testMustPromoteOnLastRank(uint8 file) public {
    vm.assume(file < 8);
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    vm.expectRevert('PromotionRequired');
    b.move(c, _from(file), _to(file));
  }

  function testPromotionByCapture(uint8 file) public {
    vm.assume(file < 7);
    uint8 captureSquare = _to(file) + 1;
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    b.initialize(o, Piece.Rook, uint64(1) << captureSquare);
    b.move(c, _from(file), captureSquare, Piece.Queen);
    assertEq(b.bitboard(c, Piece.Pawn), bytes8(0));
    assertEq(b.bitboard(c, Piece.Queen), bytes8(uint64(1) << captureSquare));
    assertEq(b.bitboard(o, Piece.Rook), bytes8(0));
  }

  function testPromotedPieceIsActive(uint8 file) public {
    vm.assume(file < 8);
    b.initialize(c, Piece.Pawn, uint64(1) << _from(file));
    b.move(c, _from(file), _to(file), Piece.Queen);
    uint8 queenPos = _to(file);
    uint8 queenDest = file < 7 ? queenPos + 1 : queenPos - 1;
    _testLegalMove(c, Piece.Queen, queenPos, queenDest);
  }

  function testCantPromoteOnNonLastRank(uint8 file) public {
    vm.assume(file < 8);
    uint8 from = c == Color.White ? 0x10+file : 0x28+file;
    uint8 to   = c == Color.White ? 0x18+file : 0x20+file;
    b.initialize(c, Piece.Pawn, uint64(1) << from);
    vm.expectRevert('InvalidPromotion');
    b.move(c, from, to, Piece.Queen);
  }

  function testNonPromotionMoveUnaffected(uint8 file) public {
    vm.assume(file < 8);
    uint8 from = c == Color.White ? 0x10+file : 0x28+file;
    uint8 to   = c == Color.White ? 0x18+file : 0x20+file;
    b.initialize(c, Piece.Pawn, uint64(1) << from);
    b.move(c, from, to);
    assertEq(b.bitboard(c, Piece.Pawn), bytes8(uint64(1) << to));
    assertEq(b.bitboard(c, Piece.Queen), bytes8(0));
  }
}

contract WhitePawnPromotionTest is PawnPromotionTest {
  constructor() PawnPromotionTest(Color.White) {}
}

contract BlackPawnPromotionTest is PawnPromotionTest {
  constructor() PawnPromotionTest(Color.Black) {}
}
