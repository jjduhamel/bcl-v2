// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@oz/token/ERC20/ERC20.sol';

contract MockERC20Token is ERC20 {
  constructor() ERC20('Mock', 'MCK') {}
  function mint(address to, uint amount) public { _mint(to, amount); }
}
