// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@aa/interfaces/IPaymaster.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@oz/utils/math/Math.sol';
import '@lib/EscrowLib.sol';
import '@lib/SharedStructs.sol';
import '@lib/ProfileLib.sol';
import './ILobby.sol';
import './IChessEngine.sol';
import './ChessEngine.sol';

contract Lobby is
  Initializable,
  UUPSUpgradeable,
  EscrowWrapper,
  ProfileWrapper,
  IPaymaster,
  ILobby
{
  using PlayerLobby for PlayerLobby.PlayerLobby;
  using ProfileLib for PlayerProfile;
  using ProfileLib for RobotProfile;

  // Lobby Settings
  bool private __allowChallenges;
  bool private __allowWagers;

  // User Roles
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ARBITER_ROLE = keccak256('ARBITER_ROLE');
  bytes32 public constant HUMAN_ROLE = keccak256('HUMAN_ROLE');
  bytes32 public constant AGENT_ROLE = keccak256('AGENT_ROLE');
  bytes32 public constant BANNED_ROLE = keccak256('BANNED_ROLE');

  // Chess engine
  ChessEngine private __currentEngine;
  mapping(address => bool) private __chessEngines;
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
    _grantRole(admin, ADMIN_ROLE);
    _grantRole(admin, ARBITER_ROLE);
    _setPlatformFee(2);
    _setGasFee(10);
  }

  function _authorizeUpgrade(address newImplementation) internal override {
    _assertIsAdmin();
  }

  /*
   * Accessors
   */

  function currentEngine() external view returns (address) { return address(__currentEngine); }

  function chessEngine(uint gameId) public view returns (ChessEngine) {
    return ChessEngine(__gameEngine[gameId]);
  }

  function _assertIsGameEngine(uint gameId) internal view {
    if (msg.sender != __gameEngine[gameId]) revert Forbidden();
  }

  function challenges(address player) external view returns (uint[] memory) {
    return _lobby(player).challenges();
  }

  function games(address player) external view returns (uint[] memory) {
    return _lobby(player).games();
  }

  function history(address player) external view returns (uint[] memory) {
    return _lobby(player).history();
  }

  function playerProfile(address player) external view
  returns (PlayerProfile memory) {
    _assertIsHuman(player);
    return _player(player);
  }

  function agentProfile(address robot) external view
  returns (RobotProfile memory) {
    _assertIsAgent(robot);
    return _agent(robot);
  }

  function gameStats(address account) external view
  returns (AccountStats memory) {
    return _stats(account);
  }

  function wagerStats(address account, address token) external view
  returns (EscrowStats memory) {
    _assertIsOwner(account);
    return escrowStats(account, token);
  }

  /*
   * Player Balances
   */

  function netEarnings(address account) external view returns (int) {
    _assertIsOwner(account);
    // Funds flow through the owner, not the seat — resolve agents to their owner before reading.
    address owner = _owner(account);
    uint gains = escrowStats(owner, address(0)).earnings;
    uint losses = escrowStats(owner, address(0)).losses;
    return int(gains)-int(losses);
  }

  function _balances(address account, address token) private view returns (int, int, uint) {
    return (
      totalBalance(account, token),
      unlockedBalance(account, token),
      lockedBalance(account, token)
    );
  }

  function currentBalance(address token) external view returns (int, int, uint) {
    return _balances(msg.sender, token);
  }

  function currentDeposit(uint gameId) external view returns (uint) {
    _assertIsPlayer(gameId);
    return currentDeposit(msg.sender, gameId).amount;
  }

  function checkPlayerBalance(address player, address token) external view returns (int, int, uint) {
    _assertIsAdmin();
    return _balances(player, token);
  }

  function checkPlayerDeposit(uint gameId, address player) external view
  returns (uint) {
    _assertIsArbiter();
    return currentDeposit(player, gameId).amount;
  }

  // This should run near the beginning of every payable function
  function _handleETHDeposit() internal {
    if (msg.value > 0) {
      _assertIsHuman(msg.sender);
      _deposit(msg.sender, msg.value, address(0));
    }
  }

  // Players only — agents hold no funds; their wagers and gas draw on the owner's balance.
  function deposit(uint amount, address token) external payable {
    _assertIsActive(msg.sender);
    _assertIsHuman(msg.sender);
    _deposit(msg.sender, amount, token);
  }

  function withdraw(address token) external {
    _assertIsHuman(msg.sender);
    _withdraw(msg.sender, token);
  }

  function _opponent(IChessEngine.GameData memory game) internal returns (address) {
    if (_controls(game.whitePlayer)) return game.blackPlayer;
    else if (_controls(game.blackPlayer)) return game.whitePlayer;
    else return address(0);
  }

  function _owner(address account) internal view returns (address) {
    if (_hasRole(account, AGENT_ROLE)) return _agent(account).owner;
    else if (_hasRole(account, HUMAN_ROLE)) return account;
    else return address(0);
  }

  function _controls(address account) internal view returns (bool) {
    if (account == address(0)) return _hasRole(msg.sender, ADMIN_ROLE);
    else if (_hasRole(msg.sender, HUMAN_ROLE)) return msg.sender == _owner(account);
    else if (_hasRole(msg.sender, AGENT_ROLE)) return msg.sender == account;
    else return false;
  }

  function _assertNotBanned(address account) internal view {
    if (_hasRole(account, BANNED_ROLE)) revert UserBanned();
    if (_hasRole(account, AGENT_ROLE)) {
      if (_hasRole(_owner(account), BANNED_ROLE)) revert UserBanned();
    }
  }

  function _assertIsActive(address account) internal view {
    _assertNotBanned(account);
    if (_hasRole(account, AGENT_ROLE)) {
      if (!_agent(account).active) revert Forbidden();
    }
  }

  function _assertIsHuman(address account) internal view {
    if (!_hasRole(account, HUMAN_ROLE)) revert Unauthorized();
  }

  function _assertIsAgent(address account) internal view {
    if (!_hasRole(account, AGENT_ROLE)) revert Unauthorized();
  }

  function _assertIsOwner(address account) internal view {
    if (msg.sender != _owner(account)) revert Unauthorized();
  }

  function _assertSenderControls(address account) internal view {
    if (!_controls(account)) revert Unauthorized();
  }

  function _assertIsRegistered(address account) internal view {
    if (account == address(0)) return;     // sentinel for global rollups
    if (!_hasRole(account, HUMAN_ROLE) && !_hasRole(account, AGENT_ROLE)) revert Unregistered();
  }

  function _assertIsUnregistered(address account) internal view {
    if (_hasRole(account, HUMAN_ROLE) || _hasRole(account, AGENT_ROLE)) revert AlreadyRegistered();
  }

  function _assertIsOpenTable(uint gameId) internal view {
    if (!_isOpenTable(gameId)) revert Forbidden();
  }

  function _assertIsPlayer(uint gameId) internal view {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (!_controls(game.whitePlayer) && !_controls(game.blackPlayer))
      revert Unauthorized();
  }

  /*
   * Player / agent profiles
   */

  function registerPlayer(
    string calldata username,
    string calldata avatar
  ) external
  {
    _assertIsUnregistered(msg.sender);
    _register(msg.sender, username, avatar);
    _grantRole(msg.sender, HUMAN_ROLE);
  }

  function agents(address owner) external view
  returns (address[] memory) {
    _assertIsHuman(owner);
    return _agents(owner);
  }

  // TODO: no agent consent yet. Any owner can claim an unregistered address as their agent,
  // including a third party's EOA that hasn't onboarded yet — `_owner(victim)` then resolves
  // to the attacker. The victim is permanently locked out of registering, and any wager sent
  // to `victim` by a third party (e.g. from a public address book) routes to the attacker.
  // Before mainnet, require proof the caller controls the agent key (e.g. an EIP-712 signature
  // from `robot` over (owner, chainId, lobby, nonce)).
  function registerAgent(
    address robot,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  )
  external payable {
    _assertIsHuman(msg.sender);
    _assertIsActive(msg.sender);
    _assertIsUnregistered(robot);
    _handleETHDeposit();
    _register(
      robot,
      msg.sender,
      nickname,
      avatar,
      agentFramework,
      baseModel,
      modelVersion
    );
    _grantRole(robot, AGENT_ROLE);
    emit AgentRegistered(msg.sender, robot);
  }

  function updateAgent(
    address robot,
    string calldata nickname,
    string calldata avatar,
    string calldata agentFramework,
    string calldata baseModel,
    string calldata modelVersion
  ) external {
    _assertIsAgent(robot);
    _assertSenderControls(robot);
    _assertNotBanned(robot);
    _agent(robot).update(nickname, avatar, agentFramework, baseModel, modelVersion);
    emit AgentUpdated(msg.sender, robot);
  }

  function suspendAgent(address robot) external {
    _assertIsAgent(robot);
    _assertIsOwner(robot);
    _agent(robot).suspend(true);
    emit AgentSuspended(msg.sender, robot);
  }

  function resumeAgent(address robot) external {
    _assertIsAgent(robot);
    _assertIsOwner(robot);
    _agent(robot).suspend(false);
    emit AgentResumed(msg.sender, robot);
  }

  function unregisterAgent(address robot) external {
    _assertIsAgent(robot);
    _assertNotBanned(robot);
    _assertIsOwner(robot);
    // Disallow unregistering agent during a game to prevent loss of funds
    if (_games(robot).length > 0) revert AgentInGame();
    _unregister(msg.sender, robot);
    _revokeRole(robot, AGENT_ROLE);
    emit AgentUnregistered(msg.sender, robot);
  }

  /*
   * Engine Interface
   */

  // Simply emits an event.  Signals that the opponent did something
  // and the client should update the record.
  function touch(uint gameId, address sender, address receiver) external
  {
    _assertIsGameEngine(gameId);
    emit TouchRecord(gameId, sender, receiver);
  }

  function _assertWagerOk(
    address player,
    uint wagerAmount,
    address wagerToken
  ) internal view {
    if (wagerAmount > 0) {
      if (!__allowWagers) revert WageringDisabled();
      if (player == address(0)) return;
      // Agents can only draw from the owner's withdrawable balance (funds locked in other games
      // don't count toward a new wager).
      if (_hasRole(player, AGENT_ROLE)) {
        if (availableBalance(_owner(player), wagerToken) < wagerAmount) revert InvalidWager();
        // TODO: We can enforce a max wager per token
      }
    }
  }

  function _create(
    address player,
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) internal returns (uint) {
    if (!__allowChallenges) revert ChallengingDisabled();
    _assertWagerOk(player, wagerAmount, wagerToken);
    _assertWagerOk(opponent, wagerAmount, wagerToken);

    // Create a new challenge on the current game engine
    uint gameId = __currentEngine.createChallenge(_stats(address(0)).created++
                                                 , player
                                                 , opponent
                                                 , startAsWhite
                                                 , timePerMove
                                                 , wagerAmount
                                                 , wagerToken);

    // Set the game engine
    __gameEngine[gameId] = address(__currentEngine);

    // Hold the wager in the owner's lobby escrow
    if (wagerAmount > 0) _escrow(_owner(player), gameId, wagerAmount, wagerToken);

    // Add to pending challenges
    _lobby(player).challenge(gameId);
    _lobby(opponent).challenge(gameId);

    // Update challenges sent/received
    _stats(player).created++;
    _stats(opponent).received++;

    emit NewChallenge(gameId, player, opponent);

    return gameId;
  }

  function _modify(
    uint gameId,
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) internal {
    ChessEngine engine = chessEngine(gameId);

    // Engine validates state + applies seat/timePerMove/wagerAmount updates,
    // and bumps currentMove to the opponent so they can accept the modified challenge.
    IChessEngine.GameData memory game = engine.modifyChallenge(gameId,
                                                               player,
                                                               startAsWhite,
                                                               timePerMove,
                                                               wagerAmount);

    address opponent = _opponent(game);
    // A modify only tops up the difference, so check against funds already locked for this game
    // deducted — matching what _escrow will actually lock.
    uint pExtra = Math.saturatingSub(wagerAmount, currentDeposit(_owner(player), gameId).amount);
    uint oExtra = Math.saturatingSub(wagerAmount, currentDeposit(_owner(opponent), gameId).amount);
    _assertWagerOk(player, pExtra, game.wagerToken);
    _assertWagerOk(opponent, oExtra, game.wagerToken);

    // Top up the owner's escrow if needed. Any over-deposit from a wager decrease stays in
    // escrow and is trimmed at game start (acceptChallenge) or returned on cancel.
    if (wagerAmount > 0) _escrow(_owner(player), gameId, wagerAmount, game.wagerToken);

    emit TouchRecord(gameId, player, opponent);
  }

  function createTable(
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) external payable returns (uint) {
    _assertSenderControls(player);
    _assertIsActive(player);
    _handleETHDeposit();
    return _create(player, address(0), startAsWhite, timePerMove, wagerAmount, wagerToken);
  }

  // Join an open table (opponent == address(0)): seat the joiner in the colour the creator left
  // open and hand the turn back to the creator to accept/decline. Terms are the table's.
  // Not _assertIsPlayer — the joiner isn't a seat yet, only the owner of the seat-to-be.
  function joinTable(uint gameId, address player) external payable
  returns (uint) {
    _assertIsOpenTable(gameId);
    _assertSenderControls(player);
    _assertIsActive(player);
    _handleETHDeposit();
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);

    // Block self -> self and agent -> owner
    address opponent = game.whitePlayer == address(0) ? game.blackPlayer
                                                      : game.whitePlayer;
    if (_owner(player) == _owner(opponent)) revert InvalidRequest();
    _assertIsActive(opponent);

    // The joiner fills the open seat — they can't pick a colour and flip the creator.
    _modify(gameId,
            player,
            game.whitePlayer == address(0),
            game.timePerMove,
            game.wagerAmount);

    // Move the table out of the global open registry into the joiner's pending set.
    _lobby(player).challenge(gameId);
    _lobby(address(0)).decline(gameId);

    return gameId;
  }

  function closeTable(uint gameId) external
  {
    _assertIsOpenTable(gameId);
    // Admins and arbiters can close any open table; otherwise the caller must hold a seat at it.
    if (!_hasRole(msg.sender, ARBITER_ROLE) &&
        !_hasRole(msg.sender, ADMIN_ROLE)) {
      _assertIsPlayer(gameId);
    }
    IChessEngine.GameData memory gameData = chessEngine(gameId).game(gameId);
    address creator = (gameData.whitePlayer == address(0)) ? gameData.blackPlayer
                                                           : gameData.whitePlayer;

    chessEngine(gameId).declineChallenge(gameId);
    _refund(_owner(creator), gameId);

    _lobby(creator).decline(gameId);
    _lobby(address(0)).decline(gameId);

    emit TableClosed(gameId, creator);
  }

  function challenge(
    address player,
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) external payable returns (uint) {
    _assertSenderControls(player);
    _assertIsActive(player);
    _assertIsRegistered(opponent);
    _assertIsActive(opponent);
    // Disallow agent -> human challenge
    if (_hasRole(player, AGENT_ROLE)) _assertIsAgent(opponent);
    _handleETHDeposit();
    return _create(player, opponent, startAsWhite, timePerMove, wagerAmount, wagerToken);
  }

  // TODO support changing wagerToken (requires refunding existing escrow and re-depositing)
  function modifyChallenge(
    uint gameId,
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) external payable {
    _assertSenderControls(player);
    _assertIsActive(player);
    _assertIsPlayer(gameId);
    _handleETHDeposit();
    _modify(gameId, player, startAsWhite, timePerMove, wagerAmount);
  }

  function acceptChallenge(uint gameId) external payable {
    _assertIsPlayer(gameId);
    // Inline state + seat + turn checks — separate `isGameState`/`isPlayersGame`/`isCurrentMove`
    // modifiers would re-decode GameData three times at this single call site.
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    if (!_controls(gameData.currentMove)) revert Unauthorized();
    _assertIsActive(gameData.currentMove);
    if (gameData.state != IChessEngine.GameState.Pending) revert IChessEngine.InvalidContractState();
    _handleETHDeposit();

    address player = gameData.currentMove;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;

    if (gameData.wagerAmount > 0) {
      // The player may already have made a partial deposit if the challenge was modified.
      _escrow(_owner(player), gameId, gameData.wagerAmount, gameData.wagerToken);

      // Refund any excess deposits.  This can occur if the wager amount is modified.
      // Escrow is keyed by owner, not seat — an agent's wager lives in its owner's account.
      _refundExcess(_owner(player), gameId, gameData.wagerAmount);
      _refundExcess(_owner(opponent), gameId, gameData.wagerAmount);

      // Charge platform fees out of both players' escrowed wagers
      _chargeFee(_owner(player), gameId, gameData.wagerToken);
      _chargeFee(_owner(opponent), gameId, gameData.wagerToken);
    }

    // Engine transitions Pending -> Started + emits GameStarted
    engine.startGame(gameId);

    _lobby(player).accept(gameId);
    _lobby(opponent).accept(gameId);
    _lobby(address(0)).track(gameId);

    _stats(player).started++;
    _stats(opponent).started++;
    _stats(address(0)).started++;

    emit ChallengeAccepted(gameId, player, opponent);
  }

  function declineChallenge(uint gameId) external {
    _assertIsPlayer(gameId);

    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory game = engine.game(gameId);

    address player;
    address opponent;
    if (_controls(game.whitePlayer)) {
      player = game.whitePlayer;
      opponent = game.blackPlayer;
    } else {
      player = game.blackPlayer;
      opponent = game.whitePlayer;
    }

    // Engine validates state + transitions Pending -> Declined
    engine.declineChallenge(gameId);

    // Return escrowed wagers to both players
    _refund(_owner(player), gameId);
    _refund(_owner(opponent), gameId);

    _lobby(player).decline(gameId);
    _lobby(opponent).decline(gameId);

    emit ChallengeDeclined(gameId, player, opponent);
  }

  function finishGame(uint gameId, IChessEngine.GameOutcome outcome) external
  {
    _assertIsGameEngine(gameId);
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address white = gameData.whitePlayer;
    address black = gameData.blackPlayer;

    _lobby(white).finish(gameId);
    _lobby(black).finish(gameId);
    _lobby(address(0)).finish(gameId);

    TokenDeposit memory wPrize = _refund(_owner(white), gameId);
    TokenDeposit memory bPrize = _refund(_owner(black), gameId);
    if (outcome == IChessEngine.GameOutcome.WhiteWon) {
      _award(_owner(white), _owner(black), bPrize);
      _stats(white).victories++;
      _stats(black).defeats++;
    } else if (outcome == IChessEngine.GameOutcome.BlackWon) {
      _award(_owner(black), _owner(white), wPrize);
      _stats(black).victories++;
      _stats(white).defeats++;
    } else if (outcome == IChessEngine.GameOutcome.Draw) {
      _stats(white).draws++;
      _stats(black).draws++;
      _stats(address(0)).draws++;
    } else {
      revert IChessEngine.InvalidContractState();
    }

    _stats(white).finished++;
    _stats(black).finished++;
    _stats(address(0)).finished++;

    emit GameFinished(gameId, white, black);
  }

  /*
   * Disputes
   */

  function disputes() external view
  returns (uint[] memory) {
    _assertIsArbiter();
    return _lobby(address(0)).disputes();
  }

  function disputeGame(uint gameId, address sender, address receiver) external
  {
    _assertIsGameEngine(gameId);
    _lobby(sender).dispute(gameId);
    _lobby(receiver).dispute(gameId);
    _lobby(address(0)).dispute(gameId);

    _stats(sender).disputes++;
    _stats(receiver).disputes++;
    _stats(address(0)).disputes++;

    emit GameDisputed(gameId, sender, receiver);
  }

  function resolveDispute(
    uint gameId,
    address white,
    address black,
    IChessEngine.GameOutcome outcome
  ) external
  {
    _assertIsGameEngine(gameId);
    if (outcome == IChessEngine.GameOutcome.Draw) {
      _stats(white).disputesWon++;
      _stats(black).disputesWon++;
    } else {
      address winner = outcome == IChessEngine.GameOutcome.WhiteWon ? white : black;
      address loser = outcome == IChessEngine.GameOutcome.WhiteWon ? black : white;
      _stats(winner).disputesWon++;
      _stats(loser).disputesLost++;
    }
    _lobby(white).resolve(gameId);
    _lobby(black).resolve(gameId);
    _lobby(address(0)).resolve(gameId);
    _stats(address(0)).disputesWon++;                 // Counts disputes resolved
    emit DisputeResolved(gameId, white, black);
  }
  /*
   * Admin / arbiter Stuff
   */

  function hasRole(bytes32 role, address account) external view returns (bool) {
    return _hasRole(account, role);
  }

  function grantRole(bytes32 role, address account) external {
    _assertIsAdmin();
    _grantRole(account, role);
  }

  function revokeRole(bytes32 role, address account) external {
    _assertIsAdmin();
    _revokeRole(account, role);
  }

  function _assertIsAdmin() internal view {
    if (!_hasRole(msg.sender, ADMIN_ROLE)) revert Unauthorized();
  }

  function _assertIsArbiter() internal view {
    if (!_hasRole(msg.sender, ARBITER_ROLE)) revert Unauthorized();
  }

  function allowChallenges(bool allow) external {
    _assertIsAdmin();
    __allowChallenges = allow;
  }

  function allowWagers(bool allow) external {
    _assertIsAdmin();
    __allowWagers = allow;
  }

  function setChessEngine(address engine) external {
    _assertIsAdmin();
    __chessEngines[engine] = true;
    __currentEngine = ChessEngine(engine);
  }

  function setPlatformFee(uint perc) external {
    _assertIsAdmin();
    _setPlatformFee(perc);
  }

  function setGasFee(uint perc) external {
    _assertIsAdmin();
    _setGasFee(perc);
  }

  function platformBalance(address token) external view returns (int) {
    _assertIsAdmin();
    return unlockedBalance(address(0), token);
  }

  function withdrawPlatformFunds(address token, address payable receiver) external {
    _assertIsAdmin();
    _releasePlatformFunds(token, receiver);
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
    if (msg.sender != address(__entryPoint)) revert Forbidden();
    _;
  }

  function setEntryPoint(IEntryPoint ep) external {
    _assertIsAdmin();
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
    uint256 maxCost
  ) external override onlyEntryPoint 
  returns (bytes memory context, uint256 validationData) {
    _assertIsAgent(op.sender);
    _assertNotBanned(op.sender);
    (address target, uint256 value, bytes4 innerSelector) = _decodeExecute(op.callData);
    // Agents custody no ETH; a sponsored op must move no value.
    if (value != 0) revert InvalidRequest();
    if (__chessEngines[target] || target == address(this)) {
      if (!_isSponsoredSelector(innerSelector)) revert Forbidden();
    } else {
      revert InvalidRequest();
    }

    address owner = _owner(op.sender);
    if (availableBalance(owner, address(0)) < maxCost + gasFee(maxCost)) {
      revert EscrowLib.InsufficientBalance();
    }
    // Carry the billable owner forward to postOp. validationData 0 == valid, no time bounds.
    return (abi.encode(owner), 0);
  }

  function postOp(
    IPaymaster.PostOpMode /* mode */,
    bytes calldata context,
    uint256 actualGasCost,
    uint256 /* actualUserOpFeePerGas */
  ) external override onlyEntryPoint {
    address owner = abi.decode(context, (address));
    _chargeGas(owner, actualGasCost);
  }

  // Decode Simple7702Account.execute(target, value, data) out of a UserOp's callData, returning
  // the wrapped engine target, the ETH value, and the inner call's selector. Uses the same
  // abi.decode the account itself uses, so the paymaster and the account agree by construction.
  function _decodeExecute(bytes calldata callData)
    private pure
    returns (address target, uint256 value, bytes4 innerSelector)
  {
    if (callData.length < 4 || bytes4(callData[0:4]) != EXECUTE_SELECTOR) revert InvalidRequest();
    bytes memory inner;
    (target, value, inner) = abi.decode(callData[4:], (address, uint256, bytes));
    if (inner.length < 4) revert InvalidRequest();
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
        || sel == ChessEngine.disputeGame.selector
        || sel == Lobby.createTable.selector
        || sel == Lobby.joinTable.selector
        || sel == Lobby.acceptChallenge.selector
        || sel == Lobby.modifyChallenge.selector
        || sel == Lobby.declineChallenge.selector
        || sel == Lobby.closeTable.selector
        || sel == Lobby.updateAgent.selector
        || sel == Lobby.challenge.selector;
  }

  /*
   * Paymaster funding / admin (keep the Lobby solvent on the EntryPoint)
   */

  // Top up the deposit the EntryPoint debits to reimburse bundlers for sponsored ops.
  function depositToEntryPoint() external payable {
    _assertIsAdmin();
    __entryPoint.depositTo{ value: msg.value }(address(this));
  }

  // Post the paymaster stake bundlers require to accept ops from the public mempool.
  function addStake(uint32 unstakeDelaySec) external payable {
    _assertIsAdmin();
    __entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
  }

  function unlockStake() external {
    _assertIsAdmin();
    __entryPoint.unlockStake();
  }

  function withdrawStake(address payable to) external {
    _assertIsAdmin();
    __entryPoint.withdrawStake(to);
  }

  function withdrawEntryPointDeposit(uint256 amount, address payable to) external {
    _assertIsAdmin();
    __entryPoint.withdrawTo(to, amount);
  }

  function entryPointDeposit() external view returns (uint256) {
    return __entryPoint.balanceOf(address(this));
  }
}
