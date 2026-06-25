// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

import '@aa/interfaces/IEntryPoint.sol';
import '@aa/interfaces/IPaymaster.sol';
import '@aa/interfaces/PackedUserOperation.sol';
import './ChessEngine.sol';
import './ILobby.sol';
import './Lobby.sol';

contract Paymaster is IPaymaster {
  Lobby private immutable __lobby;
  IEntryPoint private immutable __entryPoint;
  uint private __gasSponsorFeePerc;

  // Selector of Simple7702Account.execute(address,uint256,bytes).
  bytes4 private constant EXECUTE_SELECTOR = bytes4(keccak256('execute(address,uint256,bytes)'));

  constructor(Lobby lobby_, IEntryPoint entryPoint_) {
    __lobby = lobby_;
    __entryPoint = entryPoint_;
    __gasSponsorFeePerc = 10;
  }

  modifier onlyEntryPoint() {
    if (msg.sender != address(__entryPoint)) revert ILobby.Forbidden();
    _;
  }

  modifier onlyAdmin() {
    if (!__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender)) revert ILobby.Unauthorized();
    _;
  }

  function lobby() external view returns (Lobby) {
    return __lobby;
  }

  function entryPoint() external view returns (IEntryPoint) {
    return __entryPoint;
  }

  function setGasFee(uint perc) external onlyAdmin {
    __gasSponsorFeePerc = perc;
  }

  function gasFeePerc() public view returns (uint) {
    return __gasSponsorFeePerc;
  }

  function gasFee(uint cost) public view returns (uint96) {
    return uint96(cost * __gasSponsorFeePerc / 100);
  }

  function validatePaymasterUserOp(
    PackedUserOperation calldata op,
    bytes32 /* userOpHash */,
    uint256 maxCost
  ) external override onlyEntryPoint
  returns (bytes memory context, uint256 validationData) {
    (address target, uint256 value, bytes4 innerSelector) = _decodeExecute(op.callData);
    if (value != 0) revert ILobby.InvalidRequest();

    if (target == address(__lobby)) {
      if (!_isSponsoredLobbySelector(innerSelector)) revert ILobby.Forbidden();
    } else if (__lobby.isChessEngine(target)) {
      if (!_isSponsoredEngineSelector(innerSelector)) revert ILobby.Forbidden();
    } else {
      revert ILobby.InvalidRequest();
    }

    uint fee = gasFee(maxCost);
    address owner = __lobby.validateSponsoredAgent(op.sender, maxCost + fee);
    return (abi.encode(owner), 0);
  }

  function postOp(
    IPaymaster.PostOpMode /* mode */,
    bytes calldata context,
    uint256 actualGasCost,
    uint256 /* actualUserOpFeePerGas */
  ) external override onlyEntryPoint {
    address owner = abi.decode(context, (address));
    __lobby.chargeSponsoredGas(owner, actualGasCost, gasFee(actualGasCost));
  }

  function _decodeExecute(bytes calldata callData)
    private pure
    returns (address target, uint256 value, bytes4 innerSelector)
  {
    if (callData.length < 4 || bytes4(callData[0:4]) != EXECUTE_SELECTOR) revert ILobby.InvalidRequest();
    bytes memory inner;
    (target, value, inner) = abi.decode(callData[4:], (address, uint256, bytes));
    if (inner.length < 4) revert ILobby.InvalidRequest();
    assembly { innerSelector := mload(add(inner, 0x20)) }
  }

  function _isSponsoredEngineSelector(bytes4 sel) private pure returns (bool) {
    return sel == ChessEngine.move.selector
        || sel == ChessEngine.resign.selector
        || sel == ChessEngine.offerDraw.selector
        || sel == ChessEngine.respondDraw.selector
        || sel == ChessEngine.claimVictory.selector
        || sel == ChessEngine.disputeGame.selector;
  }

  function _isSponsoredLobbySelector(bytes4 sel) private pure returns (bool) {
    return sel == Lobby.createTable.selector
        || sel == Lobby.joinTable.selector
        || sel == Lobby.acceptChallenge.selector
        || sel == Lobby.modifyChallenge.selector
        || sel == Lobby.declineChallenge.selector
        || sel == Lobby.closeTable.selector
        || sel == Lobby.updateAgent.selector
        || sel == Lobby.challenge.selector;
  }

  function depositToEntryPoint() external payable onlyAdmin {
    __entryPoint.depositTo{ value: msg.value }(address(this));
  }

  function addStake(uint32 unstakeDelaySec) external payable onlyAdmin {
    __entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
  }

  function unlockStake() external onlyAdmin {
    __entryPoint.unlockStake();
  }

  function withdrawStake(address payable to) external onlyAdmin {
    __entryPoint.withdrawStake(to);
  }

  function withdrawEntryPointDeposit(uint256 amount, address payable to) external onlyAdmin {
    __entryPoint.withdrawTo(to, amount);
  }

  function entryPointDeposit() external view returns (uint256) {
    return __entryPoint.balanceOf(address(this));
  }
}
