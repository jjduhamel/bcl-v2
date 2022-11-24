// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

library ArrayUtils {
  function pop(uint[] storage array, uint gameId) internal returns (bool) {
    // Start from the newest challenges and go backwards
    for (uint j=array.length-1; j>=0; j--) {
      if (gameId == array[j]) {
        for (++j; j<array.length; j++) {
          array[j-1] = array[j];
        }
        array.pop();
        return true;
      }
    }
    return false;
  }

  function popLazy(uint[] storage array, uint gameId) internal returns (bool) {
    // Start from the newest challenges and go backwards
    for (uint j=array.length-1; j>=0; j--) {
      if (gameId == array[j]) {
        array[j] = array[array.length-1];
        array.pop();
        return true;
      }
    }
    return false;
  }
}
