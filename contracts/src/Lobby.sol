// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol';
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '@lib/Escrow.sol';
import './ILobby.sol';
import './IChessEngine.sol';
import './ChessEngine.sol';
import '@aa/interfaces/IPaymaster.sol';
import '@aa/interfaces/IEntryPoint.sol';

contract Lobby is
  Initializable,
  UUPSUpgradeable,
  AccessControlEnumerableUpgradeable,
  EscrowContract,
  IPaymaster,
  ILobby
{
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  struct GameStats {
    uint created;
    uint received;
    uint started;
    uint finished;
    uint won;
    uint lost;
    uint draws;
  }

  struct WagerStats {
    uint total;
    uint won;
    uint lost;
  }

  struct DisputeStats {
    uint created;
    uint received;
    uint won;
    uint lost;
  }

  struct AccountStats {
    GameStats games;
    WagerStats wagers;
    DisputeStats disputes;
  }

  struct PlayerProfile {
    string username;
    string avatar;            // Avatar URI
    uint40  createdAt;
    AccountStats stats;
    EnumerableSet.AddressSet robots;
  }

  // TODO: Handle maxWager for different token types
  struct RobotProfile {
    address owner;
    bool    active;
    string  nickname;
    string  avatar;           // Avatar URI
    string  agentFramework;   // e.g. Hermes
    string  baseModel;        // e.g. Claude Opus
    string  modelVersion;     // e.g. 4.7
    uint40  createdAt;
    AccountStats stats;
  }

  struct PlayerLobby {
    EnumerableSet.UintSet pendingChallenges;
    EnumerableSet.UintSet currentGames;
    EnumerableSet.UintSet finishedGames;
    //AccountStats stats;
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
  bytes32 public constant ROBOT_ROLE = keccak256('ROBOT_ROLE');
  bytes32 public constant ROLE_6 = keccak256('ROLE_6');
  bytes32 public constant ROLE_7 = keccak256('ROLE_7');
  bytes32 public constant ROLE_8 = keccak256('ROLE_8');

  // Player Lobby
  mapping(address => PlayerLobby) private __lobby;
  mapping(address => PlayerProfile) private __players;
  mapping(address => RobotProfile) private __robots;
  AccountStats private __platform;

  // Disputed games
  EnumerableSet.UintSet private __disputes;

  // Chess engine
  ChessEngine private __currentEngine;
  EnumerableSet.AddressSet private __chessEngines;
  // Map gameId -> ChessEngine
  mapping(uint => address) private __gameEngine;

  // ERC-4337 paymaster: the trusted EntryPoint singleton whose gas this Lobby sponsors.
  // Appended here (Lobby's own storage region, not the Escrow __gap) so the UUPS proxy
  // layout only grows — a safe append across upgrades.
  IEntryPoint private __entryPoint;

  constructor() {
    _disableInitializers();
  }

  function initialize(address admin) public initializer {
    _grantRole(ADMIN_ROLE, admin);
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

  /*
   * Stats accessors
   */

  function _stats(address account) private view
  returns (AccountStats storage) {
    return __robots[account].owner == address(0) ? __players[account].stats
                                                 : __robots[account].stats;
  }

  function statistics(address account) public view
  returns (GameStats memory) {
    return _stats(account).games;
  }

  function statistics() public view returns (GameStats memory) {
    return statistics(msg.sender);
  }

  function wagers(address account) public view
    isOwner(account)
  returns (WagerStats memory) {
    return _stats(account).wagers;
  }

  function wagers() public view returns (WagerStats memory) {
    return wagers(msg.sender);
  }

  function challengesSent(address player) public view returns (uint) {
    return _stats(player).games.created;
  }

  function challengesReceived(address player) public view returns (uint) {
    return _stats(player).games.received;
  }

  function gamesStarted(address player) public view returns (uint) {
    return _stats(player).games.started;
  }

  function gamesFinished(address player) public view returns (uint) {
    return _stats(player).games.finished;
  }

  function totalWins(address player) public view returns (uint) {
    return _stats(player).games.won;
  }

  function totalLosses(address player) public view returns (uint) {
    return _stats(player).games.lost;
  }

  function totalDraws(address player) public view returns (uint) {
    return _stats(player).games.draws;
  }

  function totalChallenges() public view returns (uint) {
    return __platform.games.created;
  }

  function totalFinishes() public view returns (uint) {
    return __platform.games.finished;
  }

  function grossWagers() public view returns (uint) {
    return _stats(msg.sender).wagers.total;
  }

  function grossWinnings() public view returns (uint) {
    return _stats(msg.sender).wagers.won;
  }

  function grossLosses() public view returns (uint) {
    return _stats(msg.sender).wagers.lost;
  }

  function netEarnings(address account) public view returns (int) {
    uint gains = _stats(msg.sender).wagers.won;
    uint losses = _stats(msg.sender).wagers.lost;
    return int(gains)-int(losses);
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

  // A seat (whitePlayer/blackPlayer) holds an agent or a human. The owner — the human who
  // runs the agent, or the human playing as themselves — is authorized to manage the game.
  modifier isPlayer(uint gameId) {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (msg.sender != ownerOf(game.whitePlayer) && msg.sender != ownerOf(game.blackPlayer)) revert IChessEngine.PlayerOnly();
    _;
  }

  modifier isCurrentMove(uint gameId) {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (msg.sender != ownerOf(game.currentMove)) revert IChessEngine.NotCurrentMove();
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

  function earnings(address token) public view
  returns (uint) {
    return releasedFunds(msg.sender, token);
  }

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

  function checkPlayerEarnings(address player, address token) public view
    isAdmin
  returns (uint) {
    return releasedFunds(player, token);
  }

  function withdraw(address token) public {
    release(msg.sender, token);
  }

  /*
   * Agents
   */

  // The human accountable for a seat: an agent's owner, or the address itself for a human.
  function ownerOf(address account) public view returns (address) {
    address owner = __robots[account].owner;
    return owner == address(0) ? account : owner;
  }

  modifier isOwner(address account) {
    if (ownerOf(account) != msg.sender) revert NotAgentOwner();
    _;
  }

  modifier isAgent(address account) {
    if (__robots[account].owner == address(0)) revert NotAnAgent();
    _;
  }

  // TODO: Remove this
  function agent(address robot) external view returns (RobotProfile memory) {
    return __robots[robot];
  }

  function agents(address owner) external view returns (address[] memory) {
    return __players[owner].robots.values();
  }

  // TODO: no agent consent yet. Any owner can claim an unregistered address as their agent
  // (including an existing human's address), making ownerOf(victim) resolve to the attacker
  // and routing the victim's winnings to them. Before mainnet, require proof the caller
  // controls the agent key (e.g. an off-chain signature from `robot` over (owner, chainId, lobby)).
  function registerAgent(
    address robot,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) external notBanned {
    if (__robots[robot].owner != address(0)) revert AgentAlreadyRegistered();
    RobotProfile storage r = __robots[robot];
    r.owner = msg.sender;
    r.active = true;
    r.nickname = nickname;
    r.avatar = avatar;
    r.agentFramework = agentFramework;
    r.baseModel = baseModel;
    r.modelVersion = modelVersion;
    r.createdAt = uint40(block.timestamp);
    __players[msg.sender].robots.add(robot);
    _grantRole(ROBOT_ROLE, robot);
    emit AgentRegistered(msg.sender, robot);
  }

  function unregisterAgent(address robot) external {
    if (__robots[robot].owner != msg.sender) revert NotAgentOwner();
    if (__lobby[robot].currentGames.length() > 0) revert AgentInGame();
    __players[msg.sender].robots.remove(robot);
    delete __robots[robot];
    _revokeRole(ROBOT_ROLE, robot);
    emit AgentUnregistered(msg.sender, robot);
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

  /*
   * Engine Interface
   */

  // TODO: Implement user registration flow
  function registerPlayer(address player) private {
  }

  // Simply emits an event.  Signals that the opponent did something
  // and the client should update the record.
  function touch(uint gameId, address sender, address receiver) external
    isGameEngine(gameId)
  {
    emit TouchRecord(gameId, sender, receiver);
  }

  function challenge(
    address sender,
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) external payable
    notBanned
    allowChallenge
    allowWager(wagerAmount, wagerToken)
    isOwner(sender)
  returns (uint) {
    registerPlayer(sender);
    registerPlayer(opponent);

    // Create a new challenge on the current game engine
    uint gameId = __currentEngine.createChallenge(__platform.games.created++
                                                 , sender
                                                 , opponent
                                                 , startAsWhite
                                                 , timePerMove
                                                 , wagerAmount
                                                 , wagerToken);

    // Set the game engine
    __gameEngine[gameId] = address(__currentEngine);

    // Hold sender's wager in lobby escrow
    if (wagerAmount > 0) {
      deposit(msg.sender, gameId, wagerToken, wagerAmount);
    }

    // Add to pending challenges
    __lobby[sender].pendingChallenges.add(gameId);
    __lobby[opponent].pendingChallenges.add(gameId);

    // Update challenges sent/received
    _stats(sender).games.created++;
    _stats(opponent).games.received++;

    emit NewChallenge(gameId, sender, opponent);

    return gameId;
  }

  function acceptChallenge(uint gameId) external payable
    notBanned
    isGameState(gameId, IChessEngine.GameState.Pending)
    isPlayer(gameId)
    isCurrentMove(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);

    address player = gameData.currentMove;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;
    if (gameData.wagerAmount > 0) {
      // The player may already have made a partial deposit if the challenge was modified.
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < gameData.wagerAmount) {
        deposit(msg.sender, gameId, gameData.wagerToken, gameData.wagerAmount - balance);
      }

      // Refund any excess deposits.  This can occur if the wager amount is modified.
      refundExcess(msg.sender, gameId, gameData.wagerAmount);
      refundExcess(ownerOf(opponent), gameId, gameData.wagerAmount);

      // Charge platform fees out of both players' escrowed wagers
      chargeFee(msg.sender, gameId, gameData.wagerToken);
      chargeFee(ownerOf(opponent), gameId, gameData.wagerToken);
    }

    // Engine transitions Pending -> Started + emits GameStarted
    engine.startGame(gameId);

    // Sanatize pending challenges
    __lobby[player].pendingChallenges.remove(gameId);
    __lobby[opponent].pendingChallenges.remove(gameId);

    // Populate current games
    __lobby[player].currentGames.add(gameId);
    __lobby[opponent].currentGames.add(gameId);

    _stats(player).games.started++;
    _stats(opponent).games.started++;
    __platform.games.started++;

    _stats(player).wagers.total += gameData.wagerAmount;
    _stats(opponent).wagers.total += gameData.wagerAmount;
    __platform.wagers.total += 2*gameData.wagerAmount;

    emit ChallengeAccepted(gameId, player, opponent);
  }

  // TODO support changing wagerToken (requires refunding existing escrow and re-depositing)
  function modifyChallenge(uint gameId, bool startAsWhite, uint timePerMove, uint wagerAmount) external payable
    notBanned
    isPlayer(gameId)
  {
    if (wagerAmount > 0 && !__allowWagers) revert WageringDisabled();
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address player = (msg.sender == ownerOf(gameData.whitePlayer)) ? gameData.whitePlayer
                                                                   : gameData.blackPlayer;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;
    address token = gameData.wagerToken;

    // Engine validates state + applies seat/timePerMove/wagerAmount updates,
    // and bumps currentMove to receiver so they can accept the modified challenge.
    engine.modifyChallenge(gameId, player, startAsWhite, timePerMove, wagerAmount);

    // Top up sender if needed. Any over-deposit from a wager decrease stays in
    // escrow and is trimmed at game start (acceptChallenge) or returned on cancel.
    if (wagerAmount > 0) {
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < wagerAmount) {
        deposit(msg.sender, gameId, token, wagerAmount - balance);
      }
    }

    emit TouchRecord(gameId, player, opponent);
  }

  function declineChallenge(uint gameId) external
    notBanned
    isPlayer(gameId)
  {
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address player = (msg.sender == ownerOf(gameData.whitePlayer)) ? gameData.whitePlayer
                                                                   : gameData.blackPlayer;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;

    // Engine validates state + transitions Pending -> Declined
    engine.declineChallenge(gameId);

    // Return escrowed wagers to both players
    refund(msg.sender, gameId);
    refund(ownerOf(opponent), gameId);

    // Sanitize pending challenges
    __lobby[player].pendingChallenges.remove(gameId);
    __lobby[opponent].pendingChallenges.remove(gameId);

    emit ChallengeDeclined(gameId, player, opponent);
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
      disburse(ownerOf(white), ownerOf(black), gameId, outcome);
    }

    // Remove from current games
    __lobby[white].currentGames.remove(gameId);
    __lobby[black].currentGames.remove(gameId);

    // Add to finished games
    __lobby[white].finishedGames.add(gameId);
    __lobby[black].finishedGames.add(gameId);

    if (outcome == IChessEngine.GameOutcome.Draw) {
      _stats(white).games.draws++;
      _stats(black).games.draws++;
      __platform.games.draws++;
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

      _stats(winner).games.won++;
      _stats(winner).wagers.won += gameData.wagerAmount;

      _stats(loser).games.lost++;
      _stats(loser).wagers.lost += gameData.wagerAmount;
    }

    _stats(white).games.finished++;
    _stats(black).games.finished++;
    __platform.games.finished++;

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
    _stats(sender).disputes.created++;
    _stats(receiver).disputes.received++;
    __platform.disputes.created++;
    emit GameDisputed(gameId, sender, receiver);
  }

  function resolveDispute(uint gameId, address winner, address loser) external
    isGameEngine(gameId)
  {
    __disputes.remove(gameId);
    _stats(winner).disputes.won++;
    _stats(loser).disputes.lost++;
    __platform.disputes.won++;             // Counts disputes resolved
    emit DisputeResolved(gameId, winner, loser);
  }

  /*
   * Paymaster (ERC-4337)
   *
   * The Lobby is an ERC-4337 paymaster: it sponsors gas for delegated agents so an agent key
   * never needs to hold ETH. The canonical EntryPoint singleton runs each UserOp, pays the
   * bundler out of this Lobby's prepaid deposit, and calls back into the two hooks below.
   * validatePaymasterUserOp decides whether to sponsor (verification phase); postOp settles
   * afterwards (a no-op in phase 1, where the platform simply absorbs the gas).
   */

  // Selector of Simple7702Account.execute(address,uint256,bytes) — the only account entry
  // point an agent UserOp invokes. Its calldata wraps the inner engine call we whitelist.
  bytes4 private constant EXECUTE_SELECTOR = bytes4(keccak256('execute(address,uint256,bytes)'));

  modifier onlyEntryPoint() {
    if (msg.sender != address(__entryPoint)) revert EntryPointOnly();
    _;
  }

  function setEntryPoint(IEntryPoint ep) external isAdmin {
    __entryPoint = ep;
  }

  function entryPoint() external view returns (IEntryPoint) {
    return __entryPoint;
  }

  // EntryPoint verification-phase callback: approve gas sponsorship for a whitelisted engine call.
  // Reverts to reject the UserOp. Reads only this Lobby's own storage (isAgent, __chessEngines),
  // satisfying ERC-7562 validation storage rules.
  function validatePaymasterUserOp(
    PackedUserOperation calldata op,
    bytes32 /* userOpHash */,
    uint256 /* maxCost */
  ) external override onlyEntryPoint isAgent(op.sender)
    returns (bytes memory context, uint256 validationData)
  {
    (address target, uint256 value, bytes4 innerSelector) = _decodeExecute(op.callData);
    if (!__chessEngines.contains(target) || value != 0) revert UnsupportedExecuteCall();
    if (!_isSponsoredSelector(innerSelector)) revert SelectorNotSponsored();

    // Carry the billable owner forward to postOp (unused in phase 1; Subproject 5 bills it).
    // validationData 0 == valid, no time bounds.
    return (abi.encode(ownerOf(op.sender)), 0);
  }

  // EntryPoint post-execution callback: phase 1 is a no-op — the platform absorbs the gas.
  // Subproject 5 replaces this body with _chargeGas(abi.decode(context,(address)), actualGasCost).
  function postOp(
    IPaymaster.PostOpMode /* mode */,
    bytes calldata /* context */,
    uint256 /* actualGasCost */,
    uint256 /* actualUserOpFeePerGas */
  ) external override onlyEntryPoint {}

  // Decode Simple7702Account.execute(target, value, data) out of a UserOp's callData, returning
  // the wrapped engine target, the ETH value, and the inner call's selector. Uses the same
  // abi.decode the account itself uses, so the paymaster and the account agree by construction.
  function _decodeExecute(bytes calldata callData)
    private pure
    returns (address target, uint256 value, bytes4 innerSelector)
  {
    if (callData.length < 4 || bytes4(callData[0:4]) != EXECUTE_SELECTOR) revert UnsupportedExecuteCall();
    bytes memory inner;
    (target, value, inner) = abi.decode(callData[4:], (address, uint256, bytes));
    if (inner.length < 4) revert UnsupportedExecuteCall();
    // First 4 bytes of `inner` (left-aligned in its first memory word) are the engine selector.
    assembly { innerSelector := mload(add(inner, 0x20)) }
  }

  // The engine calls an agent may make. This whitelist — not a spend cap — is the phase-1
  // security rail; move(uint256,string)'s selector is fixed (see CLAUDE.md).
  function _isSponsoredSelector(bytes4 sel) private pure returns (bool) {
    return sel == ChessEngine.move.selector
        || sel == ChessEngine.resign.selector
        || sel == ChessEngine.offerDraw.selector
        || sel == ChessEngine.respondDraw.selector
        || sel == ChessEngine.claimVictory.selector
        || sel == ChessEngine.disputeGame.selector;
  }

  /*
   * Paymaster funding / admin (keep the Lobby solvent on the EntryPoint)
   */

  // Top up the deposit the EntryPoint debits to reimburse bundlers for sponsored ops.
  function depositToEntryPoint() external payable isAdmin {
    __entryPoint.depositTo{ value: msg.value }(address(this));
  }

  // Post the paymaster stake bundlers require to accept ops from the public mempool.
  function addStake(uint32 unstakeDelaySec) external payable isAdmin {
    __entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
  }

  function unlockStake() external isAdmin {
    __entryPoint.unlockStake();
  }

  function withdrawStake(address payable to) external isAdmin {
    __entryPoint.withdrawStake(to);
  }

  function withdrawEntryPointDeposit(uint256 amount, address payable to) external isAdmin {
    __entryPoint.withdrawTo(to, amount);
  }

  function entryPointDeposit() external view returns (uint256) {
    return __entryPoint.balanceOf(address(this));
  }
}
