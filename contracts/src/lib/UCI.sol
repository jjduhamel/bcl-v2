// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './Bitboard.sol';

library UCI {
  function parse(string memory uci) internal pure
  returns (uint8 from, uint8 to, Piece promotion) {
    bytes memory b = bytes(uci);
    require(b.length == 4 || b.length == 5, 'InvalidMove');
    require(b[0] >= 'a' && b[0] <= 'h', 'InvalidMove');
    require(b[1] >= '1' && b[1] <= '8', 'InvalidMove');
    require(b[2] >= 'a' && b[2] <= 'h', 'InvalidMove');
    require(b[3] >= '1' && b[3] <= '8', 'InvalidMove');
    from = (uint8(b[1]) - uint8(bytes1('1'))) * 8 + (uint8(b[0]) - uint8(bytes1('a')));
    to   = (uint8(b[3]) - uint8(bytes1('1'))) * 8 + (uint8(b[2]) - uint8(bytes1('a')));
    if (b.length == 5) {
      if      (b[4] == 'q') promotion = Piece.Queen;
      else if (b[4] == 'r') promotion = Piece.Rook;
      else if (b[4] == 'b') promotion = Piece.Bishop;
      else if (b[4] == 'n') promotion = Piece.Knight;
      else revert('InvalidPromotion');
    }
  }
}
