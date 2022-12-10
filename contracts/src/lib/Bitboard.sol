// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './SignedMathI8.sol';

enum Color { White, Black }
enum Piece { Empty, Pawn, Rook, Knight, Bishop, Queen, King }

library Bitboard {
  using SignedMathI8 for int8;

  event PlayerMoved(address indexed player
                  , uint8 indexed from
                  , uint8 indexed to);
  event PieceCaptured(address indexed player
                    , Color indexed color
                    , Piece indexed piece);

  struct Bitboard {
    mapping(Color => mapping(Piece => bytes8)) __bitboard;
    mapping(Color => Piece[]) __captures;
  }

  function initialize(
    Bitboard storage b,
    Color c,
    Piece p,
    uint64 bitboard
  ) internal {
    b.__bitboard[c][p] = bytes8(bitboard);
  }

  function initialize(
    Bitboard storage b,
    Color c,
    Piece p,
    uint8 rank,
    uint8 bitboard
  ) internal {
    initialize(b, c, p, uint64(bitboard) << (8 * rank));
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
  }

  function place(Bitboard storage b, Color c, Piece p, uint8 i) internal {
    b.__bitboard[c][p] = bitboard(b, c, p) ^ bytes8(uint64(1)<<i);
  }

  function mask(uint8 i) internal view
  returns (bytes8) {
    return bytes8(uint64(1) << i);
  }

  function maskRank(uint8 r) internal view returns (bytes8) {
    return bytes8(uint64(0xFF) << (8*r));
  }

  function maskFile(uint8 f) internal view returns (bytes8) {
    return bytes8(uint64(0x0101010101010101) << f);
  }

  function rank(uint8 i) internal view returns (uint8) {
    return i/8;
  }

  function file(uint8 i) internal view returns (uint8) {
    return i%8;
  }

  function _dr(uint8 from, uint8 to) internal view returns (int8) {
    return int8(rank(to)) - int8(rank(from));
  }

  function _df(uint8 from, uint8 to) internal view returns (int8) {
    return int8(file(to)) - int8(file(from));
  }

  function bitboard(
    Bitboard storage b,
    Color c,
    Piece p
  ) internal view returns (bytes8) {
    return b.__bitboard[c][p];
  }

  function bitboard(
    Bitboard storage b,
    Color c
  ) internal view returns (bytes8) {
    return bitboard(b, c, Piece.Pawn)
         | bitboard(b, c, Piece.Rook)
         | bitboard(b, c, Piece.Knight)
         | bitboard(b, c, Piece.Bishop)
         | bitboard(b, c, Piece.Queen)
         | bitboard(b, c, Piece.King);
  }

  function bitboard(
    Bitboard storage b
  ) internal view returns (bytes8) {
    return bitboard(b, Color.White) | bitboard(b, Color.Black);
  }

  function lookup(
    Bitboard storage b,
    Color c,
    uint8 index
  ) internal view returns (Piece) {
    bytes8 m = mask(index);
    if (m & bitboard(b, c, Piece.Pawn) > 0) return Piece.Pawn;
    if (m & bitboard(b, c, Piece.Rook) > 0) return Piece.Rook;
    if (m & bitboard(b, c, Piece.Knight) > 0) return Piece.Knight;
    if (m & bitboard(b, c, Piece.Bishop) > 0) return Piece.Bishop;
    if (m & bitboard(b, c, Piece.Queen) > 0) return Piece.Queen;
    if (m & bitboard(b, c, Piece.King) > 0) return Piece.King;
    return Piece.Empty;
  }

  function _vPn(
    Bitboard storage b,
    Color c,
    uint8 from,
    uint8 to,
    bool capture
  ) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);

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
      if (rank(from) == 1) require(dr == 1 || dr == 2, 'InvalidMove');
      else require(dr == 1, 'InvalidMove');
    } else {
      if (rank(from) == 6) require(dr == -1 || dr == -2, 'InvalidMove');
      else require(dr == -1, 'InvalidMove');
    }
  }

  function _vRk(
    Bitboard storage b,
    Color c,
    uint8 from,
    uint8 to
  ) internal view {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);

    require(df == 0 || dr == 0, 'InvalidMove');
    if (dr == 0) {
      require(df != 0, 'InvalidMove');
      // Check we're not jumping over someone
      for (uint8 _df=1; _df<df.abs(); _df++) {
        if (df < 0) require(bitboard(b) & mask(from-_df) == 0, 'InvalidMove');
        else require(bitboard(b) & mask(from+_df) == 0, 'InvalidMove');
      }
    } else if (df == 0) {
      require(dr != 0, 'InvalidMove');
      // Check we're not jumping over someone
      for (uint8 _dr=1; _dr<dr.abs(); _dr++) {
        if (dr < 0) require(bitboard(b) & mask(from-_dr*8) == 0, 'InvalidMove');
        else require(bitboard(b) & mask(from+_dr*8) == 0, 'InvalidMove');
      }
    }
  }

  function _vKt(Bitboard storage b, Color c, int8 dr, int8 df) internal {
    require(dr.abs() == 1 || dr.abs() == 2, 'InvalidMove');
    if (dr.abs() == 1) require(df.abs() == 2, 'InvalidMove');
    else require(df.abs() == 1, 'InvalidMove');
  }

  function _vBp(Bitboard storage b, Color c, int8 dr, int8 df) internal {
  }

  function _vQn(Bitboard storage b, Color c, int8 dr, int8 df) internal {
  }

  function _vKg(Bitboard storage b, Color c, int8 dr, int8 df) internal {
  }

  function validate(
    Bitboard storage b,
    Color c,
    Piece p,
    uint8 from,
    uint8 to,
    bool capture
  ) internal {
    int8 dr = _dr(from, to);
    int8 df = _df(from, to);

    if (p == Piece.Empty) revert('InvalidPiece');
    else if (p == Piece.Pawn) _vPn(b, c, from, to, capture);
    else if (p == Piece.Rook) _vRk(b, c, from, to);
    else if (p == Piece.Knight) _vKt(b, c, dr, df);
    else if (p == Piece.Bishop) _vBp(b, c, dr, df);
    else if (p == Piece.Queen) _vQn(b, c, dr, df);
    else if (p == Piece.King) _vKg(b, c, dr, df);
  }

  function move(
    Bitboard storage b,
    Color c,
    Piece p,
    uint8 from,
    uint8 to
  ) internal {
    Color opp = Color(1-uint8(c));
    bytes8 cur = bitboard(b, c, p);
    bytes8 orig = mask(from);
    bytes8 dest = mask(to);
    // Ensure the origin has the corrent piece on it
    require((cur & orig) > 0, 'InvalidOrigin');
    // Ensure there's none of the players pieces on the destination
    require((bitboard(b, c) & dest) == 0, 'InvalidMove');
    // Detect if a piece was captured
    bool captured = (bitboard(b, opp) & dest) > 0;
    if (captured) {
      Piece capture = lookup(b, opp, to);
      require(capture != Piece.Empty, 'InvalidCapture');
      b.__captures[c].push(capture);
      emit PieceCaptured(msg.sender, c, capture);
    }
    // Check if it's a legal move
    validate(b, c, p, from, to, captured);
    // Update bitboard for player
    b.__bitboard[c][p] = cur^(orig|dest);
    // Update bitboard for opponent
    if (captured) {
      b.__bitboard[opp][p] = bitboard(b, opp)^dest;
    }
    emit PlayerMoved(msg.sender, from, to);
  }
}
