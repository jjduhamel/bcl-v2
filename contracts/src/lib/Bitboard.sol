// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './SignedMathI8.sol';

enum Color { White, Black }
enum Piece { Empty, Pawn, Rook, Knight, Bishop, Queen, King }

library Bitboard {
  using SignedMathI8 for int8;

  struct Bitboard {
    mapping(Color => mapping(Piece => bytes8)) __bitboard;
    mapping(Color => Piece[]) __captures;
    bool __allowKingSideCastle;
    bool __allowQueenSideCastle;
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
    b.__allowKingSideCastle = true;
    b.__allowQueenSideCastle = true;
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
    require(bitboard(b) & _mask(i) == 0, 'SquareOccupied');
    b.__bitboard[c][p] = bitboard(b, c, p) ^ bytes8(uint64(1)<<i);
  }

  function pluck(Bitboard storage b, Color c, Piece p, uint8 i) internal {
    require(bitboard(b) & _mask(i) > 0, 'SquareOccupied');
    b.__bitboard[c][p] = bitboard(b, c, p) ^ bytes8(uint64(1)<<i);
  }

  function _mask(uint8 i) internal view
  returns (bytes8) {
    return bytes8(uint64(1) << i);
  }

  function _rank(uint8 i) internal view
  returns (uint8) {
    return i / 8;
  }

  function _file(uint8 i) internal view
  returns (uint8) {
    return i % 8;
  }

  function _dr(uint8 from, uint8 to) internal view
  returns (int8) {
    return int8(_rank(to)) - int8(_rank(from));
  }

  function _df(uint8 from, uint8 to) internal view
  returns (int8) {
    return int8(_file(to)) - int8(_file(from));
  }

  function _vPn(Bitboard storage b, Color c, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    Color o = Color(1 - uint(c));
    bool capture = bitboard(b, o) & _mask(to) > 0;

    if (capture) {
      // Moved 1 sideways, note we recheck dr is 1 since
      // you otherwise it would let you capture and move
      // the pawn two squares from the homerow at once
      require(dr.abs() == 1, 'InvalidMove');
      require(df.abs() == 1, 'InvalidMove');
    } else {
      // No sideways movements
      require(df == 0, 'InvalidMove');
    }

    if (c == Color.White) {
      if (_rank(from) == 1 && dr == 2) {
        require(bitboard(b) & _mask(from+0x08) == 0, 'InvalidMove');
      } else require(dr == 1, 'InvalidMove');
    } else {
      if (_rank(from) == 6 && dr == -2) {
        require(bitboard(b) & _mask(from-0x08) == 0, 'InvalidMove');
      } else require(dr == -1, 'InvalidMove');
    }
  }

  function _vRk(Bitboard storage b, Color c, uint8 from, uint8 to) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    require(df == 0 || dr == 0, 'InvalidMove');
    if (dr == 0) {
      require(df != 0, 'InvalidMove');
      // Check we're not jumping over someone
      for (uint8 _df=1; _df<df.abs(); _df++) {
        if (df < 0) require(bitboard(b) & _mask(from-_df) == 0, 'InvalidMove');
        else require(bitboard(b) & _mask(from+_df) == 0, 'InvalidMove');
      }
    } else if (df == 0) {
      require(dr != 0, 'InvalidMove');
      // Check we're not jumping over someone
      for (uint8 _dr=1; _dr<dr.abs(); _dr++) {
        if (dr < 0) require(bitboard(b) & _mask(from-_dr*8) == 0, 'InvalidMove');
        else require(bitboard(b) & _mask(from+_dr*8) == 0, 'InvalidMove');
      }
    }
  }

  function _vKt(Bitboard storage b, Color c, uint8 from, uint8 to) internal {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    require(dr.abs() == 1 || dr.abs() == 2, 'InvalidMove');
    if (dr.abs() == 1) require(df.abs() == 2, 'InvalidMove');
    else require(df.abs() == 1, 'InvalidMove');
  }

  function _vBp(Bitboard storage b, Color c, uint8 from, uint8 to) internal {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    require(dr.abs() == df.abs(), 'InvalidMove');
    for (int8 _dx=1; _dx<int8(df.abs()); _dx++) {
      int8 _di = df > 0 ? _dx : -_dx;
      _di += (dr > 0 ? _dx : -_dx)*8;
      require(bitboard(b) & _mask(uint8(int8(from)+_di)) == 0, 'InvalidMove');
    }
  }

  function _vQn(Bitboard storage b, Color c, uint8 from, uint8 to) internal {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (dr == 0 || df == 0) _vRk(b, c, from, to);
    else _vBp(b, c, from, to);
  }

  function _vKg(Bitboard storage b, Color c, uint8 from, uint8 to) internal {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);
    if (df.abs() == 2 && dr == 0) {
      // Check the king is in starting position.  This is redundant as castling
      // gets disabled once the king moves, but still it feels like the code
      // would be incomplete without this check in place.
      if (c == Color.White) require(_rank(from) == 0x00, 'InvalidMove');
      else require(_rank(from) == 0x07, 'InvalidMove');
      require(_file(from) == 0x04, 'InvalidMove');
      if(df == 2) {
        // King side castle
        require(b.__allowKingSideCastle, 'InvalidMove');
        require(bitboard(b) & _mask(from+1) == 0, 'InvalidMove');
        require(bitboard(b) & _mask(from+2) == 0, 'InvalidMove');
        require(bitboard(b, c, Piece.Rook) & _mask(from+3) > 0, 'InvalidMove');
      } else if(df == -2) {
        // Queen side castle
        require(b.__allowQueenSideCastle, 'InvalidMove');
        require(bitboard(b) & _mask(from-1) == 0, 'InvalidMove');
        require(bitboard(b) & _mask(from-2) == 0, 'InvalidMove');
        require(bitboard(b) & _mask(from-3) == 0, 'InvalidMove');
        require(bitboard(b, c, Piece.Rook) & _mask(_rank(from)*8) > 0, 'InvalidMove');
      }
      // TODO Enforce king not in check
      // TODO Enforce king doesn't move through check
    } else {
      require(dr.abs() == 1 || df.abs() == 1, 'InvalidMove');
      require(dr.abs() <= 1 && df.abs() <= 1 , 'InvalidMove');
    }
  }

  function _validate(
    Bitboard storage b,
    Color c,
    Piece p,
    uint8 from,
    uint8 to
  ) internal {
    if (p == Piece.Empty) revert('InvalidPiece');
    else if (p == Piece.Pawn) _vPn(b, c, from, to);
    else if (p == Piece.Rook) _vRk(b, c, from, to);
    else if (p == Piece.Knight) _vKt(b, c, from, to);
    else if (p == Piece.Bishop) _vBp(b, c, from, to);
    else if (p == Piece.Queen) _vQn(b, c, from, to);
    else if (p == Piece.King) _vKg(b, c, from, to);
  }

  // Reverts on invalid move.  Returns the captured piece if any.
  function move(Bitboard storage b, Color c, uint8 from, uint8 to) internal
  returns (Piece) {
    bytes8 orig = _mask(from);
    bytes8 dest = _mask(to);
    Piece p = lookup(b, c, from);
    Color o = Color(1-uint8(c));
    // Ensure the origin has the correct piece on it and we're not moving
    // to an occupied square
    require(p != Piece.Empty, 'InvalidMove');
    require(dest & bitboard(b, c) == 0, 'InvalidMove');

    // Check if it's a legal move.  You can assume the move is legal if
    // this doesn't revert.
    _validate(b, c, p, from, to);

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
      if (b.__allowQueenSideCastle) b.__allowQueenSideCastle = false;
      if (b.__allowKingSideCastle) b.__allowKingSideCastle = false;
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
        if (b.__allowQueenSideCastle) b.__allowQueenSideCastle = false;
      } else if (_file(from) == 7) {
        // King side rook, disallow king side castling.
        if (b.__allowKingSideCastle) b.__allowKingSideCastle = false;
      }
    }

    b.__bitboard[c][p] = bitboard(b, c, p) ^ (orig | dest);
    return pc;
  }
}
