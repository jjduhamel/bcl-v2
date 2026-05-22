// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@lib/Bitboard.sol';
import '@lib/UCI.sol';
import './IChessEngine.sol';
import './ILobby.sol';
import './Lobby.sol';

contract ChessEngine is Initializable, UUPSUpgradeable, IChessEngine {
  using Bitboard for Bitboard.Bitboard;
  Lobby private __lobby;

  mapping(uint => GameData) private __games;
  mapping(uint => string[]) __moves;
  mapping(uint => Bitboard.Bitboard) __bitboards;

  // Reserved slots for future ChessEngine state additions. Adding a new state
  // variable above the gap means decrementing the gap size by the same amount,
  // preserving the storage layout across upgrades.
  uint256[46] private __gap;

  constructor() {
    _disableInitializers();
  }

  function initialize(address lobby) public initializer {
    __UUPSUpgradeable_init();
    __lobby = Lobby(lobby);
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isAdmin
  {}

  /*
   * Arbiter/Admin Stuff
   */

  modifier isAdmin() {
    if (!__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender)) revert ILobby.AdminOnly();
    _;
  }

  modifier isArbiter() {
    if (!__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender)) {
      if (!__lobby.hasRole(__lobby.ARBITER_ROLE(), msg.sender)) revert ArbiterOnly();
    }
    _;
  }

  /*
   * Modifiers
   */

  modifier isLobby() {
    if (msg.sender != address(__lobby)) revert LobbyContractOnly();
    _;
  }

  modifier hasRecord(uint gameId) {
    if (!__games[gameId].exists) revert MissingRecord();
    _;
  }

  modifier isChallenge(uint gameId) {
    if (__games[gameId].state != GameState.Pending) revert InvalidContractState();
    _;
  }

  modifier inProgress(uint gameId) {
    if (__games[gameId].state != GameState.Started) revert InvalidContractState();
    _;
  }

  modifier inDraw(uint gameId) {
    if (__games[gameId].state != GameState.Draw) revert InvalidContractState();
    _;
  }

  modifier inReview(uint gameId) {
    if (__games[gameId].state != GameState.Review) revert InvalidContractState();
    _;
  }

  modifier isFinished(uint gameId) {
    if (__games[gameId].state != GameState.Finished) revert InvalidContractState();
    _;
  }

  function isWhitePlayer(address player, uint gameId) private view returns (bool) {
    return (player == __games[gameId].whitePlayer);
  }

  function isBlackPlayer(address player, uint gameId) private view returns (bool) {
    return (player == __games[gameId].blackPlayer);
  }

  function _isPlayer(address player, uint gameId) private view returns (bool) {
    return (isWhitePlayer(player, gameId) || isBlackPlayer(player, gameId));
  }

  modifier isPlayer(uint gameId) {
    if (!_isPlayer(msg.sender, gameId)) revert PlayerOnly();
    _;
  }

  modifier isCurrentMove(uint gameId) {
    if (!_isPlayer(msg.sender, gameId)) revert PlayerOnly();
    if (msg.sender != __games[gameId].currentMove) revert NotCurrentMove();
    _;
  }

  modifier isOpponentsMove(uint gameId) {
    if (__games[gameId].currentMove != opponent(gameId)) revert NotOpponentsMove();
    _;
  }

  /*
   * Getters
   */

  function game(uint gameId) public view
    hasRecord(gameId)
  returns (GameData memory) {
    return __games[gameId];
  }

  function moves(uint gameId) public view
    hasRecord(gameId)
  returns (string[] memory) {
    return __moves[gameId];
  }

  function opponent(uint gameId) public view
    isPlayer(gameId)
  returns (address) {
    GameData storage gameData = __games[gameId];
    return isWhitePlayer(msg.sender, gameId) ? gameData.blackPlayer : gameData.whitePlayer;
  }

  function winner(uint gameId) public view
    isFinished(gameId)
  returns (address) {
    GameData storage gameData = __games[gameId];
    if (gameData.outcome == GameOutcome.WhiteWon) return gameData.whitePlayer;
    else if (gameData.outcome == GameOutcome.BlackWon) return gameData.blackPlayer;
    else return address(0);
  }

  function loser(uint gameId) public view
    isFinished(gameId)
  returns (address) {
    GameData storage gameData = __games[gameId];
    if (gameData.outcome == GameOutcome.WhiteWon) return gameData.blackPlayer;
    else if (gameData.outcome == GameOutcome.BlackWon) return gameData.whitePlayer;
    else return address(0);
  }

  /*
   * Game Clock
   */

  function timeDidExpire(uint gameId) public view
  returns (bool) {
    GameData storage gameData = __games[gameId];
    uint timeOfLastMove = gameData.timeOfLastMove;
    uint timePerMove = gameData.timePerMove;
    if (timeOfLastMove == 0) return false;
    return block.timestamp > (timeOfLastMove + timePerMove);
  }

  modifier timerExpired(uint gameId) {
    if (!timeDidExpire(gameId)) revert TimerActive();
    _;
  }

  modifier timerActive(uint gameId) {
    if (timeDidExpire(gameId)) revert TimerExpired();
    _;
  }

  /*
   * Challenging Logic
   */

  function createChallenge(
    uint gameId,
    address sender,
    address receiver,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount,
    address wagerToken
  ) public
    isLobby
  returns (uint) {
    if (timePerMove < 60) revert InvalidTimePerMove();
    address white = startAsWhite ? sender : receiver;
    address black = startAsWhite ? receiver : sender;
    __games[gameId] = GameData(
      true,
      GameState.Pending,
      GameOutcome.Undecided,
      payable(white),
      payable(black),
      receiver,
      timePerMove,
      0,
      wagerAmount,
      wagerToken
    );
    return gameId;
  }

  function declineChallenge(uint gameId) public
    isLobby
    isChallenge(gameId)
  {
    __games[gameId].state = GameState.Declined;
  }

  // TODO support changing wagerToken (requires refunding existing escrow and re-depositing)
  function modifyChallenge(
    uint gameId,
    address sender,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) public
    isLobby
    isChallenge(gameId)
  {
    if (!_isPlayer(sender, gameId)) revert PlayerOnly();
    if (timePerMove < 60) revert InvalidTimePerMove();
    GameData storage gameData = __games[gameId];
    address receiver = (sender == gameData.whitePlayer) ? gameData.blackPlayer
                                                        : gameData.whitePlayer;
    if (startAsWhite && sender == gameData.blackPlayer
    || !startAsWhite && sender == gameData.whitePlayer) {
      address white = startAsWhite ? sender : receiver;
      address black = startAsWhite ? receiver : sender;
      gameData.whitePlayer = payable(white);
      gameData.blackPlayer = payable(black);
    }
    if (timePerMove != gameData.timePerMove) {
      gameData.timePerMove = timePerMove;
    }
    if (wagerAmount != gameData.wagerAmount) {
      gameData.wagerAmount = wagerAmount;
    }
    // Bump current move to the receiver so they can accept the modified challenge
    gameData.currentMove = receiver;
  }

  /*
   * Game Logic
   */

  function startGame(uint gameId) public
    isLobby
    isChallenge(gameId)
  {
    GameData storage gameData = __games[gameId];
    __bitboards[gameId].initialize();
    gameData.state = GameState.Started;
    gameData.currentMove = gameData.whitePlayer;
    gameData.timeOfLastMove = block.timestamp;
    emit GameStarted(gameId, gameData.whitePlayer, gameData.blackPlayer);
  }

  function _applyMove(uint gameId, string memory uci) private returns (GameOutcome) {
    (uint8 from, uint8 to, Piece promotion) = UCI.parse(uci);
    Color c = isWhitePlayer(msg.sender, gameId) ? Color.White : Color.Black;
    Piece captured = __bitboards[gameId].move(c, from, to, promotion);
    if (captured == Piece.King) {
      return c == Color.White ? GameOutcome.WhiteWon : GameOutcome.BlackWon;
    }
    return GameOutcome.Undecided;
  }

  function move(uint gameId, string memory uci) public
    inProgress(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    GameOutcome outcome = _applyMove(gameId, uci);
    __moves[gameId].push(uci);
    emit PlayerMoved(gameId, msg.sender, uci);
    GameData storage gameData = __games[gameId];
    gameData.currentMove = opponent(gameId);
    gameData.timeOfLastMove = block.timestamp;
    if (outcome != GameOutcome.Undecided) {
      finishGame(gameId, outcome);
    } else {
      __lobby.touch(gameId, msg.sender, opponent(gameId));
    }
  }

  function finishGame(uint gameId, GameOutcome outcome) private {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Finished;
    gameData.outcome = outcome;
    emit GameOver(gameId, winner(gameId), loser(gameId));
    __lobby.finishGame(gameId, outcome);
  }

  function resign(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
  {
    finishGame(gameId, isWhitePlayer(msg.sender, gameId) ? GameOutcome.BlackWon
                                                         : GameOutcome.WhiteWon);
  }

  function offerDraw(uint gameId) external
    inProgress(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    address receiver = opponent(gameId);
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Draw;
    gameData.currentMove = receiver;
    emit OfferedDraw(gameId, msg.sender, receiver);
    __lobby.touch(gameId, msg.sender, receiver);
  }

  function respondDraw(uint gameId, bool accept) external
    inDraw(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    address receiver = opponent(gameId);
    GameData storage gameData = __games[gameId];
    if (accept) {
      emit AcceptedDraw(gameId, msg.sender, receiver);
      finishGame(gameId, GameOutcome.Draw);
    } else {
      gameData.state = GameState.Started;
      gameData.currentMove = receiver;
      emit DeclinedDraw(gameId, msg.sender, receiver);
    }
  }

  function claimVictory(uint gameId) external
    inProgress(gameId)
    isOpponentsMove(gameId)
    timerExpired(gameId)
  {
    finishGame(gameId, isWhitePlayer(msg.sender, gameId) ? GameOutcome.WhiteWon
                                                         : GameOutcome.BlackWon);
  }

  function disputeGame(uint gameId) external
    inProgress(gameId)
    isCurrentMove(gameId)
  {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Review;
    __lobby.disputeGame(gameId, msg.sender, opponent(gameId));
  }

  function resolveDispute(uint gameId, GameOutcome outcome) external
    inReview(gameId)
    isArbiter
  {
    GameData storage gameData = __games[gameId];
    address winner = outcome == GameOutcome.WhiteWon ? gameData.whitePlayer
                                                     : gameData.blackPlayer;
    address loser = outcome == GameOutcome.BlackWon ? gameData.whitePlayer
                                                    : gameData.blackPlayer;
    __lobby.resolveDispute(gameId, winner, loser);
    finishGame(gameId, outcome);
    emit ArbiterAction(gameId, msg.sender, outcome);
  }
}
