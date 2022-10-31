// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './ChessEngine.sol';

interface LobbyEvents {
  event CreatedChallenge(uint indexed gameId
                       , address indexed player1
                       , address indexed player2);
  event ModifiedChallenge(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event AcceptedChallenge(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event CanceledChallenge(uint indexed gameId
                        , address indexed sender
                        , address indexed receiver);
  event GameStarted(uint indexed gameId
                  , address indexed whitePlayer
                  , address indexed blackPlayer);
  event GameFinished(uint indexed gameId
                   , address indexed winner
                   , address indexed loser);
  event GameDisputed(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event PlayerMoved(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event MoveSAN(uint indexed gameId, address indexed player, string san);
  event ArbiterAction(address indexed arbiter, string comment);
}

contract Lobby is LobbyEvents {
  // Metadata
  bool private __initialized;
  string public __version;

  // Lobby Settings
  ChessEngine private __engine;
  address private __arbiter;
  bool private __allowChallenges;
  bool private __allowWagers;

  function arbiter() public returns (address) { return __arbiter; }
  function engine() public returns (address) { return address(__engine); }

  // Trusted Signer
  bool public __authEnabled;
  address public __authSigner;
  uint public __authTokenTTL;

  // Mapping player -> gameId
  mapping(address => uint[]) private __challenges;
  mapping(address => uint[]) private __games;
  mapping(address => uint[]) private __history;
  // Mapping gameId -> chessEngine
  mapping(uint => address) public __chessEngine;

  modifier isChessEngine(uint gameId) {
    require(msg.sender == __chessEngine[gameId], 'ChessEngineOnly');
    _;
  }

  modifier arbiterOnly() {
    require(msg.sender == __arbiter, 'ArbiterOnly');
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

  function initialize(address arbiter) public {
    require(!__initialized, 'Contract was already initialized');
    __arbiter = arbiter;
    __engine = new ChessEngine();
    __initialized = true;
  }

  function pop(mapping(address => uint[]) storage array, address player, uint gameId) private returns (bool) {
    uint[] storage items = array[player];

    // Start from the newest challenges and go backwards
    for (uint j=items.length-1; j>=0; j--) {
      if (gameId == items[j]) {
        for (++j; j<items.length; j++) {
          items[j-1] = items[j];
        }
        items.pop();
        return true;
      }
    }

    return false;
  }

  function popLazy(mapping(address => uint[]) storage array, address player, uint gameId) private returns (bool) {
    uint[] storage items = array[player];

    // Start from the newest challenges and go backwards
    for (uint j=items.length-1; j>=0; j--) {
      if (gameId == items[j]) {
        items[j] = items[items.length-1];
        items.pop();
        return true;
      }
    }

    return false;
  }

  function challenges() public returns (uint[] memory) {
    uint len = __challenges[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __challenges[msg.sender][j];
    }
    return out;
  }

  function games() public returns (uint[] memory) {
    uint len = __games[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __games[msg.sender][j];
    }
    return out;
  }

  function history() public returns (uint[] memory) {
    uint len = __history[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __games[msg.sender][j];
    }
    return out;
  }

  function challenge(
    address player2,
    bool startAsWhite,
    uint wagerAmount,
    uint timePerMove
  ) external payable allowChallenge allowWager(wagerAmount) {
    require(timePerMove >= 60, 'InvalidTimePerMove');
    address player1 = msg.sender;
    uint gameId = __engine.createChallenge{ value: msg.value }(
                                            payable(player1)
                                          , payable(player2)
                                          , startAsWhite
                                          , wagerAmount
                                          , timePerMove);
    __challenges[player1].push(gameId);
    __challenges[player2].push(gameId);
    __chessEngine[gameId] = address(__engine);
    emit CreatedChallenge(gameId, player1, player2);
  }

  function cancelChallenge(uint gameId, address sender, address receiver)
  external isChessEngine(gameId) {
    pop(__challenges, sender, gameId);
    //pop(__challenges, receiver, gameId);
    popLazy(__challenges, receiver, gameId);
    emit CanceledChallenge(gameId, sender, receiver);
  }

  function startGame(uint gameId, address whitePlayer, address blackPlayer)
  external isChessEngine(gameId) {
    address engine = msg.sender;
    pop(__challenges, whitePlayer, gameId);
    __games[whitePlayer].push(gameId);
    //pop(__challenges, blackPlayer, gameId);
    popLazy(__challenges, blackPlayer, gameId);   // Use this on the black player to get
                                                  // some insight into gas usage using
                                                  // for loop
    __games[blackPlayer].push(gameId);
    __engine.startGame(gameId);
    emit GameStarted(gameId, whitePlayer, blackPlayer);
  }

  function finishGame(uint gameId, address winner, address loser)
  external isChessEngine(gameId) {
    pop(__games, winner, gameId);
    __history[winner].push(gameId);
    //pop(__challenges, blackPlayer, gameId);
    popLazy(__games, loser, gameId);
    __history[loser].push(gameId);
    emit GameFinished(gameId, winner, loser);
  }

  function broadcastMove(uint gameId, address sender, address receiver)
  external isChessEngine(gameId) {
    emit PlayerMoved(gameId, sender, receiver);
  }

  /*
  function disputeGame(address _sender, address _receiver)
  external isChessEngine(gameId) {
    address _game = msg.sender;
    emit GameDisputed(_game, _sender, _receiver);
  }
  */

  /*
   * Arbiter functions
   */
  function setVersion(string memory _version)
  external arbiterOnly returns (string memory) {
    __version = _version;
    return __version;
  }

  function setArbiter(address arbiter)
  external arbiterOnly returns (address) {
    __arbiter = arbiter;
    return __arbiter;
  }

  function setChessEngine(address engine)
  external arbiterOnly returns (address) {
    __engine = ChessEngine(engine);
    return __engine;
  }

  function setAuthData(address _signer, uint _ttl, bool _enabled)
  external arbiterOnly returns (bool) {
    __authEnabled = _enabled;
    __authSigner = _signer;
    __authTokenTTL = _ttl;
    return __authEnabled;
  }

  function allowChallenges(bool _allow)
  external arbiterOnly returns (bool) {
    __allowChallenges = _allow;
    return __allowChallenges;
  }

  function allowWagers(bool _allow)
  external arbiterOnly returns (bool) {
    __allowWagers = _allow;
    return __allowWagers;
  }
}
