// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import './ChessEngine.sol';
import 'lib/ArrayUtils.sol';

interface LobbyInterface {
  event TouchRecord(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event NewChallenge(uint indexed gameId
                   , address indexed player1
                   , address indexed player2);
  event ChallengeAccepted(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event ChallengeDeclined(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event GameFinished(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event GameDisputed(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event DisputeResolved(uint indexed gameId
                      , address indexed sender
                      , address indexed receiver);
}

contract Lobby is Initializable, UUPSUpgradeable, LobbyInterface {
  using ArrayUtils for uint[];

  // Lobby Settings
  address private __arbiter;
  bool private __allowChallenges;
  bool private __allowWagers;

  // Trusted Signer
  bool public __authEnabled;
  address public __authSigner;
  uint public __authTokenTTL;

  ChessEngine private __currentEngine;
  uint __gameIndex;
  // Map gameId -> chessEngine
  mapping(uint => address) private __chessEngine;
  // Map player -> gameId
  mapping(address => uint[]) private __challenges;
  mapping(address => uint[]) private __games;
  mapping(address => uint[]) private __history;
  // List gameId[]
  uint[] private __disputes;

  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __UUPSUpgradeable_init();
    __arbiter = msg.sender;
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isArbiter
  {}

  /*
   * Chess Engine
   */

  function currentEngine() public view returns (address) { return address(__currentEngine); }

  function chessEngine(uint gameId) public view returns (address) {
    return __chessEngine[gameId];
  }

  modifier isChessEngine(uint gameId) {
    require(msg.sender == __chessEngine[gameId], 'ChessEngineOnly');
    _;
  }

  modifier allowChallenge() {
    require(__allowChallenges, 'ChallengingDisabled');
    _;
  }

  modifier allowWager(uint _amount) {
    if (_amount > 0) {
      require(__allowWagers, 'WageringDisabled');
      require(msg.value >= _amount, 'InvalidDepositAmount');
    }
    _;
  }

  function challenges() public view returns (uint[] memory) {
    return __challenges[msg.sender];
  }

  function games() public view returns (uint[] memory) {
    return __games[msg.sender];
  }

  function history() public view returns (uint[] memory) {
    return __history[msg.sender];
  }

  /*
   * Arbiter Stuff
   */

  function arbiter() public view returns (address) { return __arbiter; }

  modifier isArbiter() {
    require(msg.sender == __arbiter, 'ArbiterOnly');
    _;
  }

  function disputes() public view isArbiter returns (uint[] memory) {
    return __disputes;
  }

  function setArbiter(address newArbiter) external isArbiter {
    __arbiter = newArbiter;
  }

  function allowChallenges(bool allow) external isArbiter {
    __allowChallenges = allow;
  }

  function allowWagers(bool allow) external isArbiter {
    __allowWagers = allow;
  }

  function setChessEngine(address engine) external isArbiter {
    __currentEngine = ChessEngine(engine);
  }

  function setAuthData(address signer, uint ttl, bool enabled) external isArbiter {
    __authEnabled = enabled;
    __authSigner = signer;
    __authTokenTTL = ttl;
  }

  /*
   * User API
   */

  // Simply emits an event.  Signals that the opponent did something
  // and the client should update the record.
  function touch(uint gameId, address sender, address receiver) external
    isChessEngine(gameId)
  {
    emit TouchRecord(gameId, sender, receiver);
  }

  function challenge(
    address player2,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) external payable
    allowChallenge
    allowWager(wagerAmount)
  returns (uint) {
    require(timePerMove >= 60, 'InvalidTimePerMove');
    address player1 = msg.sender;
    address whitePlayer = startAsWhite ? player1 : player2;
    address blackPlayer = startAsWhite ? player2 : player1;
    uint gameId = __currentEngine.createChallenge{ value: msg.value }(__gameIndex++
                                                                    , player1
                                                                    , player2
                                                                    , payable(whitePlayer)
                                                                    , payable(blackPlayer)
                                                                    , timePerMove
                                                                    , wagerAmount);
    __challenges[player1].push(gameId);
    __challenges[player2].push(gameId);
    __chessEngine[gameId] = address(__currentEngine);
    emit NewChallenge(gameId, msg.sender, player2);
    return gameId;
  }

  function cancelChallenge(uint gameId, address sender, address receiver) external
    isChessEngine(gameId)
  {
    __challenges[sender].pop(gameId);
    __challenges[receiver].pop(gameId);
    emit ChallengeDeclined(gameId, sender, receiver);
  }

  function acceptChallenge(uint gameId, address sender, address receiver) external
    isChessEngine(gameId)
  {
    __challenges[sender].pop(gameId);
    __challenges[receiver].pop(gameId);
    __currentEngine.startGame(gameId);
    __games[sender].push(gameId);
    __games[receiver].push(gameId);
    emit ChallengeAccepted(gameId, sender, receiver);
  }

  function finishGame(uint gameId, address sender, address receiver) external
    isChessEngine(gameId)
  {
    __games[sender].pop(gameId);
    __games[receiver].pop(gameId);
    __history[sender].push(gameId);
    __history[receiver].push(gameId);
    emit GameFinished(gameId, sender, receiver);
  }

  /*
   * Disputes
   */

  function disputeGame(uint gameId, address sender, address receiver) external
    isChessEngine(gameId)
  {
    __disputes.push(gameId);
    emit GameDisputed(gameId, sender, receiver);
  }

  function resolveDispute(uint gameId, address whitePlayer, address blackPlayer) external
    isChessEngine(gameId)
  {
    __disputes.popLazy(gameId);
    emit DisputeResolved(gameId, whitePlayer, blackPlayer);
  }
}
