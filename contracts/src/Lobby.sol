// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '@oz/utils/Counters.sol';
import './ILobby.sol';
import './IChessEngine.sol';
import './ChessEngine.sol';

contract Lobby is
  Initializable,
  UUPSUpgradeable,
  AccessControlEnumerableUpgradeable,
  ILobby 
{
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;
  using Counters for Counters.Counter;

  // Lobby Settings
  bool private __allowChallenges;
  bool private __allowWagers;

  // Trusted Signer
  bool public __authEnabled;
  address public __authSigner;
  uint public __authTokenTTL;

  // User Roles
  bytes32 public constant ADMIN_ROLE = 0x00;
  bytes32 public constant ARBITER_ROLE = keccak256('ARBITER_ROLE');
  bytes32 public constant AMBASSADOR_ROLE = keccak256('AMBASSADOR_ROLE');
  bytes32 public constant VIP_ROLE = keccak256('VIP_ROLE');
  bytes32 public constant BANNED_ROLE = keccak256('BANNED_ROLE');
  bytes32 public constant ROLE_5 = keccak256('ROLE_5');
  bytes32 public constant ROLE_6 = keccak256('ROLE_6');
  bytes32 public constant ROLE_7 = keccak256('ROLE_7');
  bytes32 public constant ROLE_8 = keccak256('ROLE_8');

  // Player Lobby
  //Counters.Counter private __gamesCreated;
  //Counters.Counter private __gamesStarted;
  //Counters.Counter private __gamesFinished;
  // Map player -> lobby
  LobbyMetadata private __house;
  EnumerableSet.AddressSet private __users;
  mapping(address => PlayerLobby) private __lobby;
  mapping(address => PlayerMetadata) private __player;
  // Disputed games
  EnumerableSet.UintSet private __disputes;

  // Chess engine
  ChessEngine private __currentEngine;
  EnumerableSet.AddressSet private __chessEngines;
  // Map gameId -> ChessEngine
  mapping(uint => address) private __gameEngine;

  // Map player -> gameId
  //mapping(address => uint[]) private __challenges;
  //mapping(address => uint[]) private __games;
  //mapping(address => uint[]) private __player;
  // List gameId[]
  //uint[] private __disputes;

  constructor() {
    _disableInitializers();
  }

  function initialize(address admin) public initializer {
    __UUPSUpgradeable_init();
    _setupRole(ADMIN_ROLE, admin);
    _grantRole(ARBITER_ROLE, admin);
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isAdmin
  {}

  /*
   * Admin/Arbiter Stuff
   */

  modifier isAdmin() {
    _checkRole(ADMIN_ROLE);
    _;
  }

  modifier isArbiter() {
    _checkRole(ARBITER_ROLE);
    _;
  }

  function disputes() public view
    isArbiter
  returns (uint[] memory) {
    return __disputes.values();
  }

  function allowChallenges(bool allow) external
    isAdmin
  {
    __allowChallenges = allow;
  }

  function allowWagers(bool allow) external
    isAdmin
  {
    __allowWagers = allow;
  }

  function setChessEngine(address engine) external
    isAdmin
  {
    __chessEngines.add(engine);
    __currentEngine = ChessEngine(engine);
  }

  function setAuthData(address signer, uint ttl, bool enabled) external
    isAdmin
  {
    __authEnabled = enabled;
    __authSigner = signer;
    __authTokenTTL = ttl;
  }

  function grossWagers(address player) public view
    isAdmin
  returns (uint) {
    return __player[player].netWagers;
  }

  function grossWinnings(address player) public view
    isAdmin
  returns (uint) {
    return __player[player].netWinnings;
  }

  function grossLosses(address player) public view
    isAdmin
  returns (uint) {
    return __player[player].netLosses;
  }

  /*
   * Modifiers
   */

  function currentEngine() public view returns (address) { return address(__currentEngine); }

  function chessEngine(uint gameId) public view returns (ChessEngine) {
    return ChessEngine(__gameEngine[gameId]);
  }

  modifier isChessEngine() {
    require(__chessEngines.contains(msg.sender), 'ChessEngineOnly');
    _;
  }

  modifier isGameEngine(uint gameId) {
    require(msg.sender == __gameEngine[gameId], 'GameEngineOnly');
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

  modifier notBanned() {
    require(!hasRole(BANNED_ROLE, msg.sender), 'UserBanned');
    _;
  }

  /*
   * Getters
   */

  function challenges(address player) public view returns (uint[] memory) {
    return __lobby[player].pendingChallenges.values();
  }

  function games(address player) public view returns (uint[] memory) {
    return __lobby[msg.sender].currentGames.values();
  }

  function history(address player) public view returns (uint[] memory) {
    return __lobby[msg.sender].finishedGames.values();
  }

  function challengesSent(address player) public view returns (uint) {
    return __player[player].challengesSent.current();
  }

  function challengesReceived(address player) public view returns (uint) {
    return __player[player].challengesReceived.current();
  }

  function gamesStarted(address player) public view returns (uint) {
    return __player[player].gamesStarted.current();
  }

  function gamesFinished(address player) public view returns (uint) {
    uint won = totalWins(player);
    uint lost = totalLosses(player);
    uint drawn = totalDraws(player);
    return won+lost+drawn;
  }

  function totalWins(address player) public view returns (uint) {
    return __player[player].gamesWon.current();
  }

  function totalLosses(address player) public view returns (uint) {
    return __player[player].gamesLost.current();
  }

  function totalDraws(address player) public view returns (uint) {
    return __player[player].gamesDrawn.current();
  }

  function grossWagers() public view returns (uint) {
    return __player[msg.sender].netWagers;
  }

  function grossWinnings() public view returns (uint) {
    return __player[msg.sender].netWinnings;
  }

  function grossLosses() public view returns (uint) {
    return __player[msg.sender].netLosses;
  }

  function netEarnings() public view returns (int) {
    uint winnings = grossWinnings();
    uint losses = grossLosses();
    return int(winnings)-int(losses);
  }

  function totalChallenges() public view returns (uint) {
    return __house.gamesCreated.current();
  }

  function totalGames() public view returns (uint) {
    return __house.gamesStarted.current();
  }

  function totalFinishes() public view returns (uint) {
    return __house.gamesFinished.current();
  }

  /*
   * Engine Interface
   */

  function initPlayerLobby(address player1, address player2) private {
    // TODO emit events, do stuff if either player is new
    bool p1new = __users.add(player1);
    bool p2new = __users.add(player2);
    if (p1new || p2new) {
      //if (_checkRole(AMBASSADOR_ROLE, p1)) TODO
      //if (_checkRole(AMBASSADOR_ROLE, p2)) TODO
    }
  }

  // Simply emits an event.  Signals that the opponent did something
  // and the client should update the record.
  function touch(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    emit TouchRecord(gameId, sender, receiver);
  }

  function challenge(
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) external payable
    notBanned
    allowChallenge
    allowWager(wagerAmount)
  returns (uint) {
    initPlayerLobby(msg.sender, opponent);
    // Create a new challenge on the current game engine
    uint gameId = __currentEngine.createChallenge{ value: msg.value }
                                                 (__house.gamesCreated.current()
                                                 , msg.sender
                                                 , opponent
                                                 , startAsWhite
                                                 , timePerMove
                                                 , wagerAmount);
    __house.gamesCreated.increment();
    // Set the game engine
    __gameEngine[gameId] = address(__currentEngine);
    // Add to pending challenges
    __lobby[msg.sender].pendingChallenges.add(gameId);
    __lobby[opponent].pendingChallenges.add(gameId);
    // Update challenges sent/received
    __player[msg.sender].challengesSent.increment();
    __player[opponent].challengesReceived.increment();
    emit NewChallenge(gameId, msg.sender, opponent);
    return gameId;
  }

  function cancelChallenge(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    // Remove from pending challenges
    __lobby[sender].pendingChallenges.remove(gameId);
    __lobby[receiver].pendingChallenges.remove(gameId);
    emit ChallengeDeclined(gameId, sender, receiver);
  }

  function acceptChallenge(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    // Start the game
    engine.startGame(gameId);
    // Increment total games started
    __house.gamesStarted.increment();
    __house.netWagers += 2*gameData.wagerAmount;
    __house.netEarnings += 2*engine.platformFee(gameId);
    // Remove from pending challenges
    __lobby[sender].pendingChallenges.remove(gameId);
    __lobby[receiver].pendingChallenges.remove(gameId);
    // Add to current games
    __lobby[sender].currentGames.add(gameId);
    __lobby[receiver].currentGames.add(gameId);
    // Update games started
    __player[sender].gamesStarted.increment();
    __player[receiver].gamesStarted.increment();
    // Update net wagers
    __player[sender].netWagers += gameData.wagerAmount;
    __player[receiver].netWagers += gameData.wagerAmount;
    emit ChallengeAccepted(gameId, sender, receiver);
  }

  function finishGame(uint gameId, IChessEngine.GameOutcome outcome) external
    isGameEngine(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address white = gameData.whitePlayer;
    address black = gameData.blackPlayer;
    // Increment total finished games
    __house.gamesFinished.increment();
    // Remove from current games
    __lobby[white].currentGames.remove(gameId);
    __lobby[black].currentGames.remove(gameId);
    // Add to finished games
    __lobby[white].finishedGames.add(gameId);
    __lobby[black].finishedGames.add(gameId);
    // Update games won/lost/drawn
    if (outcome == IChessEngine.GameOutcome.Draw) {
      __player[white].gamesDrawn.increment();
      __player[black].gamesDrawn.increment();
    } else {
      address winner;
      address loser;
      if (outcome == IChessEngine.GameOutcome.WhiteWon) {
        winner = white;
        loser = black;
      } else {
        winner = black;
        loser = white;
      }
      // Update winner/loser
      __player[winner].gamesWon.increment();
      __player[winner].netWinnings += gameData.wagerAmount;
      __player[loser].gamesLost.increment();
      __player[loser].netLosses += gameData.wagerAmount;
    }
    emit GameFinished(gameId, white, black);
  }

  /*
   * Disputes
   */

  function disputeGame(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    __disputes.add(gameId);
    emit GameDisputed(gameId, sender, receiver);
  }

  function resolveDispute(uint gameId, address white, address black) external
    isGameEngine(gameId)
  {
    __disputes.remove(gameId);
    emit DisputeResolved(gameId, white, black);
  }
}
