// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './SignedMathI8.sol';

enum Color { White, Black }
enum Piece { Empty, Pawn, Rook, Knight, Bishop, Queen, King }

error InvalidMove();
error InvalidPiece();
error PromotionRequired();
error InvalidPromotion();
error SquareOccupied();
error SquareEmpty();

library Bitboard {
  using SignedMathI8 for int8;

  struct Bitboard {
    mapping(Color => mapping(Piece => bytes8)) __bitboard;
    mapping(Color => Piece[]) __captures;
    bool[2] __allowKingSideCastle;
    bool[2] __allowQueenSideCastle;
  }

  function initialize(Bitboard storage b, Color c, Piece p, bytes8 bb) internal {
    b.__bitboard[c][p] = bb;
  }

  function initialize(Bitboard storage b, Color c, Piece p, uint64 bb) internal {
    initialize(b, c, p, bytes8(bb));
  }

  function initialize(Bitboard storage b, Color c, Piece p, uint8 r, uint8 bb) internal {
    initialize(b, c, p, uint64(bb) << (8 * r));
  }

  function initialize(Bitboard storage b) internal {
    // Place white pieces
    initialize(b, Color.White, Piece.Pawn, 1, 0xFF);
    initialize(b, Color.White, Piece.Rook, 0x81);
    initialize(b, Color.White, Piece.Knight, 0x42);
    initialize(b, Color.White, Piece.Bishop, 0x24);
    initialize(b, Color.White, Piece.Queen, 0x08);
    initialize(b, Color.White, Piece.King, 0x10);
    // Place black pieces
    initialize(b, Color.Black, Piece.Pawn, 6, 0xFF);
    initialize(b, Color.Black, Piece.Rook, 7, 0x81);
    initialize(b, Color.Black, Piece.Knight, 7, 0x42);
    initialize(b, Color.Black, Piece.Bishop, 7, 0x24);
    initialize(b, Color.Black, Piece.Queen, 7, 0x08);
    initialize(b, Color.Black, Piece.King, 7, 0x10);
    // Setup everything else
    b.__allowKingSideCastle[0] = true;
    b.__allowKingSideCastle[1] = true;
    b.__allowQueenSideCastle[0] = true;
    b.__allowQueenSideCastle[1] = true;
  }

  function bitboard(Bitboard storage b, Color c, Piece p) internal view
  returns (bytes8) {
    return b.__bitboard[c][p];
  }

  function bitboard(Bitboard storage b, Color c) internal view
  returns (bytes8) {
    return bitboard(b, c, Piece.Pawn)
         | bitboard(b, c, Piece.Rook)
         | bitboard(b, c, Piece.Knight)
         | bitboard(b, c, Piece.Bishop)
         | bitboard(b, c, Piece.Queen)
         | bitboard(b, c, Piece.King);
  }

  function bitboard(Bitboard storage b) internal view
  returns (bytes8) {
    return bitboard(b, Color.White) | bitboard(b, Color.Black);
  }

  function captures(Bitboard storage b, Color c) internal view
  returns (Piece[] memory) {
    return b.__captures[c];
  }

  function lookup(Bitboard storage b, Color c, uint8 i) internal view
  returns (Piece) {
    bytes8 m = _mask(i);
    if (m & bitboard(b, c, Piece.Pawn) > 0) return Piece.Pawn;
    if (m & bitboard(b, c, Piece.Rook) > 0) return Piece.Rook;
    if (m & bitboard(b, c, Piece.Knight) > 0) return Piece.Knight;
    if (m & bitboard(b, c, Piece.Bishop) > 0) return Piece.Bishop;
    if (m & bitboard(b, c, Piece.Queen) > 0) return Piece.Queen;
    if (m & bitboard(b, c, Piece.King) > 0) return Piece.King;
    return Piece.Empty;
  }

  function lookup(Bitboard storage b, uint8 i) internal view
  returns (Piece) {
    Piece p = lookup(b, Color.White, i);
    if (p == Piece.Empty) return lookup(b, Color.Black, i);
    else return p;
  }

  function place(Bitboard storage b, Color c, Piece p, uint8 i) internal {
    if (bitboard(b) & _mask(i) != 0) revert SquareOccupied();
    b.__bitboard[c][p] = bitboard(b, c, p) ^ bytes8(uint64(1)<<i);
  }

  function pluck(Bitboard storage b, Color c, Piece p, uint8 i) internal {
    if (bitboard(b) & _mask(i) == 0) revert SquareEmpty();
    b.__bitboard[c][p] = bitboard(b, c, p) ^ bytes8(uint64(1)<<i);
  }

  function _mask(uint8 i) internal pure
  returns (bytes8) {
    return bytes8(uint64(1) << i);
  }

  function _rank(uint8 i) internal pure
  returns (uint8) {
    return i / 8;
  }

  function _file(uint8 i) internal pure
  returns (uint8) {
    return i % 8;
  }

  function _dr(uint8 from, uint8 to) internal pure
  returns (int8) {
    return int8(_rank(to)) - int8(_rank(from));
  }

  function _df(uint8 from, uint8 to) internal pure
  returns (int8) {
    return int8(_file(to)) - int8(_file(from));
  }

  function _vPn(Bitboard storage b, Color c, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    Color o = Color(1 - uint(c));
    bool capture = bitboard(b, o) & _mask(to) > 0;

    if (capture) {
      if (dr.abs() != 1) revert InvalidMove();
      if (df.abs() != 1) revert InvalidMove();
    } else {
      // No sideways movements
      if (df != 0) revert InvalidMove();
    }

    if (c == Color.White) {
      if (_rank(from) == 1 && dr == 2) {
        if (bitboard(b) & _mask(from+0x08) != 0) revert InvalidMove();
      } else if (dr != 1) revert InvalidMove();
    } else {
      if (_rank(from) == 6 && dr == -2) {
        if (bitboard(b) & _mask(from-0x08) != 0) revert InvalidMove();
      } else if (dr != -1) revert InvalidMove();
    }
  }

  function _vRk(Bitboard storage b, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (df != 0 && dr != 0) revert InvalidMove();
    if (dr == 0) {
      if (df == 0) revert InvalidMove();
      // Check we're not jumping over someone
      for (uint8 _df=1; _df<df.abs(); _df++) {
        if (df < 0) { if (bitboard(b) & _mask(from-_df) != 0) revert InvalidMove(); }
        else { if (bitboard(b) & _mask(from+_df) != 0) revert InvalidMove(); }
      }
    } else {
      // Check we're not jumping over someone
      for (uint8 _dr=1; _dr<dr.abs(); _dr++) {
        if (dr < 0) { if (bitboard(b) & _mask(from-_dr*8) != 0) revert InvalidMove(); }
        else { if (bitboard(b) & _mask(from+_dr*8) != 0) revert InvalidMove(); }
      }
    }
  }

  function _vKt(uint8 from, uint8 to) internal pure {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (dr.abs() != 1 && dr.abs() != 2) revert InvalidMove();
    if (dr.abs() == 1) { if (df.abs() != 2) revert InvalidMove(); }
    else { if (df.abs() != 1) revert InvalidMove(); }
  }

  function _vBp(Bitboard storage b, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (dr.abs() != df.abs()) revert InvalidMove();
    // Check bishop won't jump over other pieces
    for (int8 _dx=1; _dx<int8(df.abs()); _dx++) {
      int8 _di = df > 0 ? _dx : -_dx;
      _di += (dr > 0 ? _dx : -_dx)*8;
      if (bitboard(b) & _mask(uint8(int8(from)+_di)) != 0) revert InvalidMove();
    }
  }

  function _vQn(Bitboard storage b, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (dr == 0 || df == 0) _vRk(b, from, to);
    else _vBp(b, from, to);
  }

  function _vKg(Bitboard storage b, Color c, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (df.abs() == 2 && dr == 0) {
      // Check the king is in starting position.  This is redundant as castling
      // gets disabled once the king moves, but still it feels like the code
      // would be incomplete without this check in place.
      if (c == Color.White) { if (_rank(from) != 0x00) revert InvalidMove(); }
      else { if (_rank(from) != 0x07) revert InvalidMove(); }
      if (_file(from) != 0x04) revert InvalidMove();
      if(df == 2) {
        // King side castle
        if (!b.__allowKingSideCastle[uint(c)]) revert InvalidMove();
        if (bitboard(b) & _mask(from+1) != 0) revert InvalidMove();
        if (bitboard(b) & _mask(from+2) != 0) revert InvalidMove();
        if (bitboard(b, c, Piece.Rook) & _mask(from+3) == 0) revert InvalidMove();
      } else if(df == -2) {
        // Queen side castle
        if (!b.__allowQueenSideCastle[uint(c)]) revert InvalidMove();
        if (bitboard(b) & _mask(from-1) != 0) revert InvalidMove();
        if (bitboard(b) & _mask(from-2) != 0) revert InvalidMove();
        if (bitboard(b) & _mask(from-3) != 0) revert InvalidMove();
        if (bitboard(b, c, Piece.Rook) & _mask(_rank(from)*8) == 0) revert InvalidMove();
      }
      // TODO Enforce king not in check
      // TODO Enforce king doesn't move through check
    } else {
      if (dr.abs() != 1 && df.abs() != 1) revert InvalidMove();
      if (dr.abs() > 1 || df.abs() > 1) revert InvalidMove();
    }
  }

  function _validate(
    Bitboard storage b,
    Color c,
    Piece p,
    uint8 from,
    uint8 to
  ) internal view {
    if (p == Piece.Empty) revert InvalidPiece();
    else if (p == Piece.Pawn) _vPn(b, c, from, to);
    else if (p == Piece.Rook) _vRk(b, from, to);
    else if (p == Piece.Knight) _vKt(from, to);
    else if (p == Piece.Bishop) _vBp(b, from, to);
    else if (p == Piece.Queen) _vQn(b, from, to);
    else if (p == Piece.King) _vKg(b, c, from, to);
  }

  function _isPromotionSquare(Color c, uint8 to) internal pure returns (bool) {
    return c == Color.White ? _rank(to) == 7 : _rank(to) == 0;
  }

  // Reverts on invalid move.  Returns the captured piece if any.
  function move(Bitboard storage b, Color c, uint8 from, uint8 to, Piece promotion) internal
  returns (Piece) {
    return _move(b, c, from, to, promotion);
  }

  // Reverts on invalid move.  Returns the captured piece if any.
  function move(Bitboard storage b, Color c, uint8 from, uint8 to) internal
  returns (Piece) {
    return _move(b, c, from, to, Piece.Empty);
  }

  function _move(Bitboard storage b, Color c, uint8 from, uint8 to, Piece promotion) private
  returns (Piece) {
    bytes8 orig = _mask(from);
    bytes8 dest = _mask(to);
    Piece p = lookup(b, c, from);
    Color o = Color(1-uint8(c));
    // Ensure the origin has the correct piece on it and we're not moving
    // to an occupied square
    if (p == Piece.Empty) revert InvalidMove();
    if (dest & bitboard(b, c) != 0) revert InvalidMove();

    // Check if it's a legal move.  You can assume the move is legal if
    // this doesn't revert.
    _validate(b, c, p, from, to);

    // Promotion checks happen after validation so illegal pawn moves still
    // revert with InvalidMove rather than PromotionRequired.
    if (p == Piece.Pawn) {
      if (_isPromotionSquare(c, to)) {
        if (promotion == Piece.Empty) revert PromotionRequired();
        if (promotion == Piece.Pawn || promotion == Piece.King) revert InvalidPromotion();
      } else {
        if (promotion != Piece.Empty) revert InvalidPromotion();
      }
    }

    // Detect if a piece was captured
    Piece pc = lookup(b, o, to);
    if (pc != Piece.Empty) {
      // Vanish piece from opponent bitboard
      b.__bitboard[o][pc] = bitboard(b, o, pc) ^ dest;
      b.__captures[c].push(pc);
    }

    // Handle castling.  Note we already checked that castling is allowed.
    if (p == Piece.King) {
      int8 dr = _dr(from, to);
      int8 df = _df(from, to);
      // Regardless of whether it's a castle, if you move the king then
      // castling is permanantly disallowed.
      if (b.__allowQueenSideCastle[uint(c)]) {
        b.__allowQueenSideCastle[uint(c)] = false;
      }
      if (b.__allowKingSideCastle[uint(c)]) {
        b.__allowKingSideCastle[uint(c)] = false;
      }
      // Update the location of the rooks if we're castling.  The king
      // location will be updated later in the final step.
      if (df == 2 && dr == 0) {
        // King side
        bytes8 rm = _mask(from+1) | _mask(_rank(from)*8 + 7);
        b.__bitboard[c][Piece.Rook] = bitboard(b, c, Piece.Rook) ^ rm;
      } else if(df == -2 && dr == 0) {
        // Queen side
        bytes8 rm = _mask(from-1) | _mask(_rank(from)*8);
        b.__bitboard[c][Piece.Rook] = bitboard(b, c, Piece.Rook) ^ rm;
      }
    } else if (p == Piece.Rook) {
      if (_file(from) == 0) {
        // Queen side rook, disallow queen side castling.
        if (b.__allowQueenSideCastle[uint(c)]) {
          b.__allowQueenSideCastle[uint(c)] = false;
        }
      } else if (_file(from) == 7) {
        // King side rook, disallow king side castling.
        if (b.__allowKingSideCastle[uint(c)]) {
          b.__allowKingSideCastle[uint(c)] = false;
        }
      }
    }

    b.__bitboard[c][p] = bitboard(b, c, p) ^ (orig | dest);

    if (p == Piece.Pawn && _isPromotionSquare(c, to)) {
      b.__bitboard[c][Piece.Pawn] = bitboard(b, c, Piece.Pawn) ^ dest;
      b.__bitboard[c][promotion] = bitboard(b, c, promotion) ^ dest;
    }

    return pc;
  }
}
