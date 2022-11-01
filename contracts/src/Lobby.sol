// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './GameEvents.sol';
import './ChessEngine.sol';

contract Lobby is GameEvents {
  // Metadata
  bool private __initialized;
  string public __version;

  // Lobby Settings
  ChessEngine private __engine;
  address private __arbiter;
  bool private __allowChallenges;
  bool private __allowWagers;

  // Trusted Signer
  bool public __authEnabled;
  address public __authSigner;
  uint public __authTokenTTL;

  // Mapping player -> gameId
  mapping(address => uint[]) private __challenges;
  mapping(address => uint[]) private __games;
  mapping(address => uint[]) private __history;
  // Mapping gameId -> chessEngine
  mapping(uint => address) private __chessEngine;

  function initialize() public {
    require(!__initialized, 'Contract was already initialized');
    __arbiter = msg.sender;
    __initialized = true;
  }

  /*
   * Chess Engine
   */

  function currentEngine() public view returns (address) { return address(__engine); }

  function chessEngine(uint gameId) public view returns (address) {
    return __chessEngine[gameId];
  }

  modifier isChessEngine(uint gameId) {
    require(msg.sender == __chessEngine[gameId], 'ChessEngineOnly');
    _;
  }

  function challenges() public view returns (uint[] memory) {
    uint len = __challenges[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __challenges[msg.sender][j];
    }
    return out;
  }

  function games() public view returns (uint[] memory) {
    uint len = __games[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __games[msg.sender][j];
    }
    return out;
  }

  function history() public view returns (uint[] memory) {
    uint len = __history[msg.sender].length;
    uint[] memory out = new uint[](len);
    for (uint j=0; j<len; j++) {
      out[j] = __games[msg.sender][j];
    }
    return out;
  }

  /*
   * Arbiter Related Stuff
   */

  function arbiter() public view returns (address) { return __arbiter; }

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

  /*
   * Challenge Related Stuff
   */

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

  /*
   * Game Related Stuff
   */

  function startGame(uint gameId, address whitePlayer, address blackPlayer)
  external isChessEngine(gameId) {
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
   * Arbiter Functions
   */

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
  function setVersion(string memory newVersion) external arbiterOnly {
    __version = newVersion;
  }

  function setArbiter(address newArbiter) external arbiterOnly {
    __arbiter = newArbiter;
  }

  function setChessEngine(address newEngine) external arbiterOnly {
    __engine = ChessEngine(newEngine);
  }

  function setAuthData(address signer, uint ttl, bool enabled) external arbiterOnly {
    __authEnabled = enabled;
    __authSigner = signer;
    __authTokenTTL = ttl;
  }

  function allowChallenges(bool allow) external arbiterOnly {
    __allowChallenges = allow;
  }

  function allowWagers(bool allow) external arbiterOnly {
    __allowWagers = allow;
  }
}
