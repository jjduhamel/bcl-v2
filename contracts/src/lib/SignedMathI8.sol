// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMathI8 {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int8 a, int8 b) internal pure returns (int8) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int8 a, int8 b) internal pure returns (int8) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int8 a, int8 b) internal pure returns (int8) {
        // Formula from the book "Hacker's Delight"
        int8 x = (a & b) + ((a ^ b) >> 1);
        return x + (int8(uint8(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int8 n) internal pure returns (uint8) {
        unchecked {
            // must be unchecked in order to support `n = type(int8).min`
            return uint8(n >= 0 ? n : -n);
        }
    }
}
