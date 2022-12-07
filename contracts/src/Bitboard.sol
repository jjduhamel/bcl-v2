// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

library Bitboard {
  enum Color { White, Black }
  enum Piece { Empty, Pawn, Rook, Knight, Bishop, Queen, King }


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
    Bitboard storage board,
    Color color,
    Piece piece,
    uint64 bitboard
  ) internal {
    board.__bitboard[color][piece] = bytes8(bitboard);
  }

  function initialize(
    Bitboard storage board,
    Color color,
    Piece piece,
    uint8 rank,
    uint8 bitboard
  ) internal {
    initialize(board, color, piece, uint64(bitboard) << (8 * rank));
  }

  function initialize(Bitboard storage board) internal {
    // Place white pieces
    initialize(board, Color.White, Piece.Pawn, 1, 0xFF);
    initialize(board, Color.White, Piece.Rook, 0x81);
    initialize(board, Color.White, Piece.Knight, 0x42);
    initialize(board, Color.White, Piece.Bishop, 0x24);
    initialize(board, Color.White, Piece.Queen, 0x08);
    initialize(board, Color.White, Piece.King, 0x10);
    // Place black pieces
    initialize(board, Color.Black, Piece.Pawn, 6, 0xFF);
    initialize(board, Color.Black, Piece.Rook, 7, 0x81);
    initialize(board, Color.Black, Piece.Knight, 7, 0x42);
    initialize(board, Color.Black, Piece.Bishop, 7, 0x24);
    initialize(board, Color.Black, Piece.Queen, 7, 0x08);
    initialize(board, Color.Black, Piece.King, 7, 0x10);
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

  function bitboard(
    Bitboard storage board,
    Color color,
    Piece piece
  ) internal view returns (bytes8) {
    return board.__bitboard[color][piece];
  }

  function bitboard(
    Bitboard storage board,
    Color color
  ) internal view returns (bytes8) {
    return bitboard(board, color, Piece.Pawn)
         | bitboard(board, color, Piece.Rook)
         | bitboard(board, color, Piece.Knight)
         | bitboard(board, color, Piece.Bishop)
         | bitboard(board, color, Piece.Queen)
         | bitboard(board, color, Piece.King);
  }

  function bitboard(
    Bitboard storage board
  ) internal view returns (bytes8) {
    return bitboard(board, Color.White) | bitboard(board, Color.Black);
  }

  function lookup(Bitboard storage board, Color color, uint8 index) internal view
  returns (Piece) {
    bytes8 m = mask(index);
    if (m & bitboard(board, color, Piece.Pawn) > 0) return Piece.Pawn;
    if (m & bitboard(board, color, Piece.Rook) > 0) return Piece.Rook;
    if (m & bitboard(board, color, Piece.Knight) > 0) return Piece.Knight;
    if (m & bitboard(board, color, Piece.Bishop) > 0) return Piece.Bishop;
    if (m & bitboard(board, color, Piece.Queen) > 0) return Piece.Queen;
    if (m & bitboard(board, color, Piece.King) > 0) return Piece.King;
    return Piece.Empty;
  }

  function _validatePawn(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to,
    bool capture
  ) internal {
    bytes8 orig = mask(from);
    bytes8 dest = mask(to);
    int8 di = int8(to)-int8(from);
    int8 dr = di / 8;
    int8 df = di % 8;
    if (color == Color.White) {
      if (capture) {
        require(di == 7 || di == 9, 'InvalidMove');
        // Prevent piece from crossing the left/right edges of the board
        if(file(from) == 0) {
          require(df == 1, 'InvalidMove');
        } else if (file(from) == 7) {
          require(df == -1, 'InvalidMove');
        }
      } else {
        require(df==0, 'InvalidMove');
        if (rank(from) == 1) {
          require(dr == 1 || dr == 2, 'InvalidMove');
        } else {
          require(dr == 1, 'InvalidMove');
        }
      }
    } else {
      /*
      if (capture) {
        require((to == from-7) || (to == from-9), 'InvalidCapture');
      } else if ((orig & rank(6)) > 0) {
        require((to == from-8) || (to == from-16), 'InvalidMove');
      } else {
        require(to == from-8, 'InvalidMove');
      }
      */
    }
  }

  function _validateRook(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to
  ) internal
  returns (bool) {
    return true;
  }

  function _validateKnight(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to
  ) internal
  returns (bool) {
    return true;
  }

  function _validateBishop(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to
  ) internal
  returns (bool) {
    return true;
  }

  function _validateQueen(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to
  ) internal
  returns (bool) {
    return true;
  }

  function _validateKing(
    Bitboard storage board,
    Color color,
    uint8 from,
    uint8 to
  ) internal
  returns (bool) {
    return true;
  }

  function validate(
    Bitboard storage board,
    Color color,
    Piece piece,
    uint8 from,
    uint8 to,
    bool capture
  ) internal {
    if (piece == Piece.Empty) revert('InvalidPiece');
    else if (piece == Piece.Pawn) _validatePawn(board, color, from, to, capture);
    else if (piece == Piece.Rook) _validateRook(board, color, from, to);
    else if (piece == Piece.Knight) _validateKnight(board, color, from, to);
    else if (piece == Piece.Bishop) _validateBishop(board, color, from, to);
    else if (piece == Piece.Queen) _validateQueen(board, color, from, to);
    else if (piece == Piece.King) _validateKing(board, color, from, to);
  }

  function move(
    Bitboard storage board,
    Color color,
    Piece piece,
    uint8 from,
    uint8 to
  ) internal {
    Color opp = Color(1-uint8(color));
    bytes8 cur = bitboard(board, color, piece);
    bytes8 orig = mask(from);
    bytes8 dest = mask(to);
    // Ensure the origin has the corrent piece on it
    require((cur & orig) > 0, 'InvalidOrigin');
    // Ensure there's none of the players pieces on the destination
    require((bitboard(board, color) & dest) == 0, 'InvalidDestination');
    // Detect if a piece was captured
    bool captured = (bitboard(board, opp) & dest) > 0;
    if (captured) {
      Piece capture = lookup(board, opp, to);
      require(capture != Piece.Empty, 'InvalidCapture');
      board.__captures[color].push(capture);
      emit PieceCaptured(msg.sender, color, capture);
    }
    // Check if it's a legal move
    validate(board, color, piece, from, to, captured);
    // Update bitboard for player
    board.__bitboard[color][piece] = cur^(orig|dest);
    // Update bitboard for opponent
    if (captured) {
      board.__bitboard[opp][piece] = bitboard(board, opp)^dest;
    }
    emit PlayerMoved(msg.sender, from, to);
  }
}
