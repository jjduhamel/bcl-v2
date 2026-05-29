// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@aa/interfaces/IPaymaster.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@lib/Escrow.sol';
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
  using ProfileLib for ProfileLib.PlayerProfile;
  using ProfileLib for ProfileLib.RobotProfile;

  // Lobby Settings
  bool private __allowChallenges;
  bool private __allowWagers;

  // User Roles
  bytes32 public constant ADMIN_ROLE = 0x00;
  bytes32 public constant ARBITER_ROLE = keccak256('ARBITER_ROLE');
  bytes32 internal constant AMBASSADOR_ROLE = keccak256('AMBASSADOR_ROLE');
  bytes32 internal constant VIP_ROLE = keccak256('VIP_ROLE');
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
    _assertAdmin();
  }

  /*
   * Accessors
   */

  function currentEngine() public view returns (address) { return address(__currentEngine); }

  function chessEngine(uint gameId) public view returns (ChessEngine) {
    return ChessEngine(__gameEngine[gameId]);
  }

  function _assertGameEngine(uint gameId) internal view {
    if (msg.sender != __gameEngine[gameId]) revert GameEngineOnly();
  }

  function challenges(address player) public view returns (uint[] memory) {
    return _lobby(player).challenges();
  }

  function games(address player) public view returns (uint[] memory) {
    return _lobby(player).games();
  }

  function history(address player) public view returns (uint[] memory) {
    return _lobby(player).history();
  }

  function playerProfile(address player) external view
  returns (ProfileLib.PlayerProfile memory) {
    _assertRegistered(player);
    return _player(player);
  }

  function agentProfile(address robot) external view
  returns (ProfileLib.RobotProfile memory) {
    _assertRegistered(robot);
    return _agent(robot);
  }

  function gameStats(address account) public view
  returns (ProfileLib.AccountStats memory) {
    return _stats(account);
  }

  function wagerStats(address account, address token) public view
  returns (Escrow.EscrowStats memory) {
    _assertOwner(account);
    return escrowStats(account, token);
  }

  /*
   * Player Balances
   */

  function netEarnings(address account) public view returns (int) {
    _assertOwner(account);
    // Funds flow through the owner, not the seat — resolve agents to their owner before reading.
    address owner = ownerOf(account);
    uint gains = escrowStats(owner, address(0)).earnings;
    uint losses = escrowStats(owner, address(0)).losses;
    return int(gains)-int(losses);
  }

  function earnings(address token) public view
  returns (uint) {
    return availableBalance(msg.sender, token);
  }

  function currentDeposit(uint gameId) public view returns (uint) {
    _assertPlayersGame(gameId);
    return currentDeposit(msg.sender, gameId).amount;
  }

  function checkPlayerDeposit(uint gameId, address player) public view
  returns (uint) {
    _assertArbiter();
    return currentDeposit(player, gameId).amount;
  }

  function checkPlayerEarnings(address player, address token) public view
  returns (uint) {
    _assertAdmin();
    return availableBalance(player, token);
  }

  function deposit(uint amount, address token) external payable {
    _assertRegistered(msg.sender);
    deposit(msg.sender, amount, token);
  }

  function withdraw(address token) external {
    _assertRegistered(msg.sender);
    withdraw(msg.sender, token);
  }

  /*
   * Player / agent profiles
   */

  function _isBanned(address account) private view returns (bool) {
    if (_hasRole(account, BANNED_ROLE)) return true;
    // Reach the agent's owner via direct storage (skips ownerOf's _assertRegistered, which
    // would recurse: _assertRegistered -> _isBanned -> ownerOf -> _assertRegistered).
    address owner = _agent(account).owner;
    return owner != address(0) && _hasRole(owner, BANNED_ROLE);
  }

  function _assertRegistered(address account) internal view {
    if (account == address(0)) return;     // sentinel for global rollups
    if (_isBanned(account)) revert UserBanned();
    if (_player(account).createdAt == 0 &&
        _agent(account).createdAt == 0
    ) revert Unregistered();
  }

  function _assertUnregistered(address account) internal view {
    if (_player(account).createdAt != 0 ||
        _agent(account).createdAt != 0
    ) revert AlreadyRegistered();
  }

  function registerPlayer(
    address player,
    string calldata username,
    string calldata avatar
  ) external
  {
    _assertUnregistered(player);
    _register(player, username, avatar);
  }

  function agents(address owner) external view
  returns (address[] memory) {
    _assertRegistered(owner);
    return _agents(owner);
  }

  // The human accountable for a seat: an agent's owner, or the address itself for a human.
  function ownerOf(address account) internal view returns (address) {
    _assertRegistered(account);
    address owner = _agent(account).owner;
    return owner == address(0) ? account : owner;
  }

  function _assertOwner(address account) internal view {
    if (_isBanned(account) || _isBanned(ownerOf(account))) revert UserBanned();
    if (ownerOf(account) != msg.sender) revert NotAgentOwner();
  }

  function _assertAgent(address account) internal view {
    if (_agent(account).owner == address(0)) revert NotAnAgent();
  }

  // TODO: no agent consent yet. Any owner can claim an unregistered address as their agent,
  // including a third party's EOA that hasn't onboarded yet — `ownerOf(victim)` then resolves
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
  public payable {
    _assertRegistered(msg.sender);
    _assertUnregistered(robot);
    // Deposit any ETH user sends to fund gas budget
    if (msg.value > 0) deposit(msg.sender, msg.value, address(0));
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
    _assertOwner(robot);
    _agent(robot).update(nickname, avatar, agentFramework, baseModel, modelVersion);
    emit AgentUpdated(msg.sender, robot);
  }

  function suspendAgent(address robot) external {
    _assertOwner(robot);
    _agent(robot).suspend(true);
    emit AgentSuspended(msg.sender, robot);
  }

  function resumeAgent(address robot) external {
    _assertOwner(robot);
    _agent(robot).suspend(false);
    emit AgentResumed(msg.sender, robot);
  }

  function unregisterAgent(address robot) external {
    _assertOwner(robot);
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
    _assertGameEngine(gameId);
    emit TouchRecord(gameId, sender, receiver);
  }

  function createTable(
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) external payable returns (uint) {
    _assertOwner(player);
    return _create(player, address(0), startAsWhite, timePerMove, wagerAmount, wagerToken);
  }

  // Join an open table (opponent == address(0)): seat the joiner in their chosen colour and
  // hand the turn back to the creator to accept/decline. Terms are the table's; colour is the
  // joiner's. Not _assertPlayersGame — the joiner isn't a seat yet, only the owner of the seat-to-be.
  function joinTable(uint gameId, address player, bool startAsWhite) external payable
  returns (uint) {
    _assertOwner(player);
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);

    // Block self -> self and agent -> owner
    address opponent = game.whitePlayer == address(0) ? game.blackPlayer
                                                      : game.whitePlayer;
    if (ownerOf(player) == ownerOf(opponent)) revert InvalidPlayer();

    _modify(gameId, player, startAsWhite, game.timePerMove, game.wagerAmount);

    // Move the table out of the global open registry into the joiner's pending set.
    _lobby(player).challenge(gameId);
    _lobby(address(0)).decline(gameId);

    return gameId;
  }

  function challenge(
    address player,
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) external payable returns (uint) {
    _assertOwner(player);
    _assertRegistered(opponent);
    return _create(player, opponent, startAsWhite, timePerMove, wagerAmount, wagerToken);
  }

  function _create(
    address player,
    address opponent,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) internal returns (uint) {
    // `allowChallenge` gate inlined (single caller).
    if (!__allowChallenges) revert ChallengingDisabled();
    if (wagerAmount > 0) {
      if (!__allowWagers) revert WageringDisabled();
      if (wagerToken == address(0) && msg.value < wagerAmount) revert InvalidDepositAmount();
    }

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

    // Hold sender's wager in lobby escrow
    if (wagerAmount > 0) {
      deposit(ownerOf(player), wagerAmount, wagerToken);
      lock(ownerOf(player), gameId, wagerAmount, wagerToken);
    }

    // Add to pending challenges
    _lobby(player).challenge(gameId);
    _lobby(opponent).challenge(gameId);

    // Update challenges sent/received
    _stats(player).created++;
    _stats(opponent).received++;

    emit NewChallenge(gameId, player, opponent);

    return gameId;
  }

  // TODO support changing wagerToken (requires refunding existing escrow and re-depositing)
  function modifyChallenge(
    uint gameId,
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) external payable {
    _assertOwner(player);
    _assertPlayersGame(gameId);
    _modify(gameId, player, startAsWhite, timePerMove, wagerAmount);
  }

  function _modify(
    uint gameId,
    address player,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) internal {
    if (wagerAmount > 0 && !__allowWagers) revert WageringDisabled();
    ChessEngine engine = chessEngine(gameId);

    // Engine validates state + applies seat/timePerMove/wagerAmount updates,
    // and bumps currentMove to the opponent so they can accept the modified challenge.
    engine.modifyChallenge(gameId, player, startAsWhite, timePerMove, wagerAmount);
    IChessEngine.GameData memory gameData = engine.game(gameId);

    // Top up the caller's escrow if needed. Any over-deposit from a wager decrease stays in
    // escrow and is trimmed at game start (acceptChallenge) or returned on cancel.
    if (wagerAmount > 0) {
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < wagerAmount) {
        deposit(ownerOf(player), wagerAmount-balance, gameData.wagerToken);
        lock(ownerOf(player), gameId, wagerAmount-balance, gameData.wagerToken);
      }
    }

    emit TouchRecord(gameId, player, gameData.currentMove);
  }

  function _assertPlayersGame(uint gameId) internal view {
    IChessEngine.GameData memory game = chessEngine(gameId).game(gameId);
    if (msg.sender != ownerOf(game.whitePlayer) &&
        msg.sender != ownerOf(game.blackPlayer)) revert IChessEngine.PlayerOnly();
  }

  function acceptChallenge(uint gameId) external payable {
    // Inline state + seat + turn checks — separate `isGameState`/`isPlayersGame`/`isCurrentMove`
    // modifiers would re-decode GameData three times at this single call site.
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    if (gameData.state != IChessEngine.GameState.Pending) revert IChessEngine.InvalidContractState();
    if (msg.sender != ownerOf(gameData.whitePlayer) &&
        msg.sender != ownerOf(gameData.blackPlayer)) revert IChessEngine.PlayerOnly();
    if (msg.sender != ownerOf(gameData.currentMove)) revert IChessEngine.NotCurrentMove();

    address player = gameData.currentMove;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;
    if (gameData.wagerAmount > 0) {
      // The player may already have made a partial deposit if the challenge was modified.
      uint balance = currentDeposit(msg.sender, gameId).amount;
      if (balance < gameData.wagerAmount) {
        deposit(ownerOf(player), gameData.wagerAmount-balance, gameData.wagerToken);
        lock(ownerOf(player), gameId, gameData.wagerAmount-balance, gameData.wagerToken);
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

    _lobby(player).accept(gameId);
    _lobby(opponent).accept(gameId);
    _lobby(address(0)).track(gameId);

    _stats(player).started++;
    _stats(opponent).started++;
    _stats(address(0)).started++;

    emit ChallengeAccepted(gameId, player, opponent);
  }

  function revokeTable(uint gameId) external {
    _assertRegistered(msg.sender);
    _assertPlayersGame(gameId);
    if (!_isOpenTable(gameId)) revert NotAnOpenTable();
    IChessEngine.GameData memory gameData = chessEngine(gameId).game(gameId);
    address creator = (gameData.whitePlayer == address(0)) ? gameData.blackPlayer
                                                           : gameData.whitePlayer;

    chessEngine(gameId).declineChallenge(gameId);
    refund(msg.sender, gameId);

    _lobby(creator).decline(gameId);
    _lobby(address(0)).decline(gameId);

    emit TableClosed(gameId, creator);
  }

  function closeTable(uint gameId) external
  {
    _assertArbiter();
    if (!_isOpenTable(gameId)) revert NotAnOpenTable();
    IChessEngine.GameData memory gameData = chessEngine(gameId).game(gameId);
    address creator = (gameData.whitePlayer == address(0)) ? gameData.blackPlayer
                                                           : gameData.whitePlayer;

    chessEngine(gameId).declineChallenge(gameId);
    refund(ownerOf(creator), gameId);

    _lobby(creator).decline(gameId);
    _lobby(address(0)).decline(gameId);

    emit TableClosed(gameId, creator);
  }

  function declineChallenge(uint gameId) external {
    _assertRegistered(msg.sender);
    _assertPlayersGame(gameId);
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address player = (msg.sender == ownerOf(gameData.whitePlayer)) ? gameData.whitePlayer
                                                                   : gameData.blackPlayer;
    address opponent = (player == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;

    // Engine validates state + transitions Pending -> Declined
    engine.declineChallenge(gameId);

    // Return escrowed wagers to both players
    refund(ownerOf(msg.sender), gameId);
    refund(ownerOf(opponent), gameId);

    _lobby(player).decline(gameId);
    _lobby(opponent).decline(gameId);

    emit ChallengeDeclined(gameId, player, opponent);
  }

  function finishGame(uint gameId, IChessEngine.GameOutcome outcome) external
  {
    _assertGameEngine(gameId);
    ChessEngine engine = chessEngine(gameId);
    IChessEngine.GameData memory gameData = engine.game(gameId);
    address white = gameData.whitePlayer;
    address black = gameData.blackPlayer;

    // Payout winner / split on draw
    if (gameData.wagerAmount > 0) {
      disburse(ownerOf(white), ownerOf(black), gameId, outcome);
    }

    _lobby(white).finish(gameId);
    _lobby(black).finish(gameId);
    _lobby(address(0)).finish(gameId);

    if (outcome == IChessEngine.GameOutcome.Draw) {
      _stats(white).draws++;
      _stats(black).draws++;
      _stats(address(0)).draws++;
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

      _stats(winner).victories++;
      _stats(loser).defeats++;
    }

    _stats(white).finished++;
    _stats(black).finished++;
    _stats(address(0)).finished++;

    emit GameFinished(gameId, white, black);
  }

  /*
   * Disputes
   */

  function disputes() public view
  returns (uint[] memory) {
    _assertArbiter();
    return _lobby(address(0)).disputes();
  }

  function disputeGame(uint gameId, address sender, address receiver) external
  {
    _assertGameEngine(gameId);
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
    _assertGameEngine(gameId);
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

  function hasRole(bytes32 role, address account) public view returns (bool) {
    return _hasRole(account, role);
  }

  function grantRole(bytes32 role, address account) external {
    _assertAdmin();
    _grantRole(account, role);
  }

  function revokeRole(bytes32 role, address account) external {
    _assertAdmin();
    _revokeRole(account, role);
  }

  function _assertAdmin() internal view {
    if (!_hasRole(msg.sender, ADMIN_ROLE)) revert AdminOnly();
  }

  function _assertArbiter() internal view {
    if (!_hasRole(msg.sender, ARBITER_ROLE)) revert IChessEngine.ArbiterOnly();
  }

  function allowChallenges(bool allow) external {
    _assertAdmin();
    __allowChallenges = allow;
  }

  function allowWagers(bool allow) external {
    _assertAdmin();
    __allowWagers = allow;
  }

  function setChessEngine(address engine) external {
    _assertAdmin();
    __chessEngines[engine] = true;
    __currentEngine = ChessEngine(engine);
  }

  function setPlatformFee(uint perc) external {
    _assertAdmin();
    _setPlatformFee(perc);
  }

  function platformBalance(address token) public view returns (uint) {
    _assertAdmin();
    return availableBalance(address(0), token);
  }

  function withdrawPlatformFunds(address token, address payable receiver) public {
    _assertAdmin();
    releasePlatformFunds(token, receiver);
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

  function setEntryPoint(IEntryPoint ep) external {
    _assertAdmin();
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
    _assertAgent(op.sender);
    (address target, uint256 value, bytes4 innerSelector) = _decodeExecute(op.callData);
    if (!__chessEngines[target] || value != 0) revert UnsupportedExecuteCall();
    if (!_isSponsoredSelector(innerSelector)) revert SelectorNotSponsored();

    address owner = ownerOf(op.sender);
    if (availableBalance(owner, address(0)) < maxCost + gasFee(maxCost)) {
      revert Escrow.InsufficientBalance();
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
    chargeGas(owner, actualGasCost);
  }

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
  function depositToEntryPoint() external payable {
    _assertAdmin();
    __entryPoint.depositTo{ value: msg.value }(address(this));
  }

  // Post the paymaster stake bundlers require to accept ops from the public mempool.
  function addStake(uint32 unstakeDelaySec) external payable {
    _assertAdmin();
    __entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
  }

  function unlockStake() external {
    _assertAdmin();
    __entryPoint.unlockStake();
  }

  function withdrawStake(address payable to) external {
    _assertAdmin();
    __entryPoint.withdrawStake(to);
  }

  function withdrawEntryPointDeposit(uint256 amount, address payable to) external {
    _assertAdmin();
    __entryPoint.withdrawTo(to, amount);
  }

  function entryPointDeposit() external view returns (uint256) {
    return __entryPoint.balanceOf(address(this));
  }
}
