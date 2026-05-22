// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '@lib/Escrow.sol';
import './ILobby.sol';
import './IChessEngine.sol';
import './ChessEngine.sol';

contract Lobby is
  Initializable,
  UUPSUpgradeable,
  AccessControlEnumerableUpgradeable,
  Escrow,
  ILobby
{
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  struct LobbyMetadata {
    uint gamesCreated;
    uint gamesStarted;
    uint gamesFinished;
    uint netWagers;
    uint netEarnings;
  }

  // TODO This should include disputesSent, disputesReceieved, disputesWon, disputesLost
  struct PlayerMetadata {
    uint challengesSent;
    uint challengesReceived;
    uint gamesStarted;
    uint gamesWon;
    uint gamesLost;
    uint gamesDrawn;
    uint netWagers;
    uint netWinnings;
    uint netLosses;
    uint totalDisputes;
    uint disputesWon;
    uint disputesLost;
  }

  struct PlayerLobby {
    EnumerableSet.UintSet pendingChallenges;
    EnumerableSet.UintSet currentGames;
    EnumerableSet.UintSet finishedGames;
  }

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
  LobbyMetadata private __lounge;
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

  constructor() {
    _disableInitializers();
  }

  function initialize(address admin) public initializer {
    __UUPSUpgradeable_init();
    _setupRole(ADMIN_ROLE, admin);
    _grantRole(ARBITER_ROLE, admin);
    _setPlatformFee(2);
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isAdmin
  {}

  /*
   * Admin/Arbiter Stuff
   */

  modifier isAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) revert AdminOnly();
    _;
  }

  modifier isArbiter() {
    if (!hasRole(ARBITER_ROLE, msg.sender)) revert IChessEngine.ArbiterOnly();
    _;
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
   * Platform Fees
   */

  function setPlatformFee(uint perc) public
    isAdmin
  { _setPlatformFee(perc); }

  function platformFee(uint gameId) public view
  returns (uint) {
    return _platformFee(chessEngine(gameId).game(gameId).wagerAmount);
  }

  function profit(address token) public view
    isAdmin
  returns (uint) {
    return releasedFunds(address(0), token);
  }

  function withdrawPlatformFunds(address token, address payable receiver) public
    isAdmin
  {
    releasePlatformFunds(token, receiver);
  }

  /*
   * Modifiers
   */

  function currentEngine() public view returns (address) { return address(__currentEngine); }

  function chessEngine(uint gameId) public view returns (ChessEngine) {
    return ChessEngine(__gameEngine[gameId]);
  }

  modifier isChessEngine() {
    if (!__chessEngines.contains(msg.sender)) revert ChessEngineOnly();
    _;
  }

  modifier isGameEngine(uint gameId) {
    if (msg.sender != __gameEngine[gameId]) revert GameEngineOnly();
    _;
  }

  modifier isGameState(uint gameId, IChessEngine.GameState state) {
    if (chessEngine(gameId).game(gameId).state != state) revert IChessEngine.InvalidContractState();
    _;
  }

  modifier isPlayer(uint gameId) {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (msg.sender != game.whitePlayer && msg.sender != game.blackPlayer) revert IChessEngine.PlayerOnly();
    _;
  }

  modifier isCurrentMove(uint gameId) {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (msg.sender != game.whitePlayer && msg.sender != game.blackPlayer) revert IChessEngine.PlayerOnly();
    if (msg.sender != game.currentMove) revert IChessEngine.NotCurrentMove();
    _;
  }

  modifier allowChallenge() {
    if (!__allowChallenges) revert ChallengingDisabled();
    _;
  }

  modifier allowWager(uint wagerAmount, address wagerToken) {
    if (wagerAmount > 0) {
      if (!__allowWagers) revert WageringDisabled();
      if (wagerToken == address(0) && msg.value < wagerAmount) revert InvalidDepositAmount();
    }
    _;
  }

  modifier notBanned() {
    if (hasRole(BANNED_ROLE, msg.sender)) revert UserBanned();
    _;
  }

  /*
   * Player Balances
   */

  function currentDeposit(uint gameId) public view
    isPlayer(gameId)
  returns (uint) {
    return currentDeposit(msg.sender, gameId).amount;
  }

  function checkPlayerDeposit(uint gameId, address player) public view
    isArbiter
  returns (uint) {
    return currentDeposit(player, gameId).amount;
  }

  function earnings(address token) public view
  returns (uint) {
    return releasedFunds(msg.sender, token);
  }

  function checkPlayerEarnings(address player, address token) public view
    isAdmin
  returns (uint) {
    return releasedFunds(player, token);
  }

  function withdraw(address token) public {
    release(msg.sender, token);
  }

  /*
   * Getters
   */

  function challenges(address player) public view returns (uint[] memory) {
    return __lobby[player].pendingChallenges.values();
  }

  function games(address player) public view returns (uint[] memory) {
    return __lobby[player].currentGames.values();
  }

  function history(address player) public view returns (uint[] memory) {
    return __lobby[player].finishedGames.values();
  }

  function challengesSent(address player) public view returns (uint) {
    return __player[player].challengesSent;
  }

  function challengesReceived(address player) public view returns (uint) {
    return __player[player].challengesReceived;
  }

  function gamesStarted(address player) public view returns (uint) {
    return __player[player].gamesStarted;
  }

  function gamesFinished(address player) public view returns (uint) {
    uint won = totalWins(player);
    uint lost = totalLosses(player);
    uint drawn = totalDraws(player);
    return won+lost+drawn;
  }

  function totalWins(address player) public view returns (uint) {
    return __player[player].gamesWon;
  }

  function totalLosses(address player) public view returns (uint) {
    return __player[player].gamesLost;
  }

  function totalDraws(address player) public view returns (uint) {
    return __player[player].gamesDrawn;
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
    return __lounge.gamesCreated;
  }

  function totalGames() public view returns (uint) {
    return __lounge.gamesStarted;
  }

  function totalFinishes() public view returns (uint) {
    return __lounge.gamesFinished;
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
    uint wagerAmount,
    address wagerToken
  ) external payable
    notBanned
    allowChallenge
    allowWager(wagerAmount, wagerToken)
  returns (uint) {
    initPlayerLobby(msg.sender, opponent);

    // Create a new challenge on the current game engine
    uint gameId = __currentEngine.createChallenge(__lounge.gamesCreated
                                                 , msg.sender
                                                 , opponent
                                                 , startAsWhite
                                                 , timePerMove
                                                 , wagerAmount
                                                 , wagerToken);
    __lounge.gamesCreated++;

    // Set the game engine
    __gameEngine[gameId] = address(__currentEngine);

    // Hold sender's wager in lobby escrow
    if (wagerAmount > 0) {
      deposit(msg.sender, gameId, wagerToken, wagerAmount);
    }

    // Add to pending challenges
    __lobby[msg.sender].pendingChallenges.add(gameId);
    __lobby[opponent].pendingChallenges.add(gameId);

    // Update challenges sent/received
    __player[msg.sender].challengesSent++;
    __player[opponent].challengesReceived++;
    emit NewChallenge(gameId, msg.sender, opponent);
    return gameId;
  }

  function acceptChallenge(uint gameId) external payable
    notBanned
    isGameState(gameId, IChessEngine.GameState.Pending)
    isCurrentMove(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);

    address opponent = (msg.sender == gameData.whitePlayer) ? gameData.blackPlayer
                                                            : gameData.whitePlayer;
    if (gameData.wagerAmount > 0) {
      // The player may already have made a partial deposit if the challenge was modified.
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < gameData.wagerAmount) {
        deposit(msg.sender, gameId, gameData.wagerToken, gameData.wagerAmount - balance);
      }

      // Refund any excess deposits.  This can occur if the wager amount is modified.
      refundExcess(msg.sender, gameId, gameData.wagerAmount);
      refundExcess(opponent, gameId, gameData.wagerAmount);

      // Charge platform fees out of both players' escrowed wagers
      chargeFee(msg.sender, gameId, gameData.wagerToken);
      chargeFee(opponent, gameId, gameData.wagerToken);
      __lounge.netEarnings += 2 * uint(_platformFee(gameData.wagerAmount));
    }

    // Engine transitions Pending -> Started + emits GameStarted
    engine.startGame(gameId);

    // Sanatize pending challenges
    __lobby[msg.sender].pendingChallenges.remove(gameId);
    __lobby[opponent].pendingChallenges.remove(gameId);

    // Populate current games
    __lobby[msg.sender].currentGames.add(gameId);
    __lobby[opponent].currentGames.add(gameId);

    // Platform metadata
    __lounge.gamesStarted++;
    __lounge.netWagers += 2*gameData.wagerAmount;

    // Player metadata
    __player[msg.sender].gamesStarted++;
    __player[msg.sender].netWagers += gameData.wagerAmount;

    // Opponent metadata
    __player[opponent].gamesStarted++;
    __player[opponent].netWagers += gameData.wagerAmount;

    emit ChallengeAccepted(gameId, msg.sender, opponent);
  }

  // TODO support changing wagerToken (requires refunding existing escrow and re-depositing)
  function modifyChallenge(uint gameId, bool startAsWhite, uint timePerMove, uint wagerAmount) external payable
    notBanned
    isPlayer(gameId)
  {
    if (wagerAmount > 0 && !__allowWagers) revert WageringDisabled();
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address opponent = (msg.sender == gameData.whitePlayer) ? gameData.blackPlayer
                                                            : gameData.whitePlayer;
    address token = gameData.wagerToken;

    // Engine validates state + applies seat/timePerMove/wagerAmount updates,
    // and bumps currentMove to receiver so they can accept the modified challenge.
    engine.modifyChallenge(gameId, msg.sender, startAsWhite, timePerMove, wagerAmount);

    // Top up sender if needed. Any over-deposit from a wager decrease stays in
    // escrow and is trimmed at game start (acceptChallenge) or returned on cancel.
    if (wagerAmount > 0) {
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < wagerAmount) {
        deposit(msg.sender, gameId, token, wagerAmount - balance);
      }
    }

    emit TouchRecord(gameId, msg.sender, opponent);
  }

  function declineChallenge(uint gameId) external
    notBanned
    isPlayer(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address opponent = (msg.sender == gameData.whitePlayer) ? gameData.blackPlayer
                                                            : gameData.whitePlayer;

    // Engine validates state + transitions Pending -> Declined
    engine.declineChallenge(gameId);

    // Return escrowed wagers to both players
    refund(msg.sender, gameId);
    refund(opponent, gameId);

    // Sanitize pending challenges
    __lobby[msg.sender].pendingChallenges.remove(gameId);
    __lobby[opponent].pendingChallenges.remove(gameId);

    emit ChallengeDeclined(gameId, msg.sender, opponent);
  }

  function finishGame(uint gameId, IChessEngine.GameOutcome outcome) external
    isGameEngine(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address white = gameData.whitePlayer;
    address black = gameData.blackPlayer;

    // Payout winner / split on draw
    if (gameData.wagerAmount > 0) {
      disburse(white, black, gameId, outcome);
    }

    // Increment total finished games
    __lounge.gamesFinished++;

    // Remove from current games
    __lobby[white].currentGames.remove(gameId);
    __lobby[black].currentGames.remove(gameId);

    // Add to finished games
    __lobby[white].finishedGames.add(gameId);
    __lobby[black].finishedGames.add(gameId);

    // Update games won/lost/drawn
    if (outcome == IChessEngine.GameOutcome.Draw) {
      __player[white].gamesDrawn++;
      __player[black].gamesDrawn++;
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
      __player[winner].gamesWon++;
      __player[winner].netWinnings += gameData.wagerAmount;
      __player[loser].gamesLost++;
      __player[loser].netLosses += gameData.wagerAmount;
    }

    emit GameFinished(gameId, white, black);
  }

  /*
   * Disputes
   */

  function disputes() public view
    isArbiter
  returns (uint[] memory) {
    return __disputes.values();
  }

  function disputeGame(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    __disputes.add(gameId);
    __player[sender].totalDisputes++;
    __player[receiver].totalDisputes++;
    emit GameDisputed(gameId, sender, receiver);
  }

  function resolveDispute(uint gameId, address winner, address loser) external
    isGameEngine(gameId)
  {
    __disputes.remove(gameId);
    __player[winner].disputesWon++;
    __player[loser].disputesLost++;
    emit DisputeResolved(gameId, winner, loser);
  }
}
