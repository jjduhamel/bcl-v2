pragma solidity >=0.4.22 <0.9.0;

// token (160 bits) | amount (96 bits)
struct TokenDeposit {
  address token;
  uint96 amount;
}
