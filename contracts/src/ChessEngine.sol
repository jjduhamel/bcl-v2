// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@lib/Bitboard.sol';
import '@lib/UCI.sol';
import '@lib/Escrow.sol';
import './IChessEngine.sol';
import './Lobby.sol';

contract ChessEngine is Initializable, UUPSUpgradeable, IChessEngine, Escrow {
  using Bitboard for Bitboard.Bitboard;
  Lobby private __lobby;

  mapping(uint => GameData) private __games;
  // map gameId -> moves (uci)
  mapping(uint => string[]) __moves;
  // map gameId -> bitboards
  mapping(uint => Bitboard.Bitboard) __bitboards;

  // Platform fees
  uint __platformFeePerc;
  uint __platformFeeMin;

  constructor() {
    _disableInitializers();
  }

  function initialize(address lobby) public initializer {
    __UUPSUpgradeable_init();
    __lobby = Lobby(lobby);
    __platformFeePerc = 1;
    __platformFeeMin = 0;
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isAdmin
  {}

  /*
   * Arbiter/Admin Stuff
   */

  modifier isAdmin() {
    require(__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender), 'AdminOnly');
    _;
  }

  modifier isArbiter() {
    if (!__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender)) {
      require(__lobby.hasRole(__lobby.ARBITER_ROLE(), msg.sender), 'ArbiterOnly');
    }
    _;
  }

  function setPlatformFee(uint perc) public
    isAdmin
  { __platformFeePerc = perc; }

  function setMinPlatformFee(uint amount) public
    isAdmin
  { __platformFeeMin = amount; }

  function profit(address token) public view
    isArbiter
  returns (uint) {
    return earnings(address(0), token);
  }

  function withdraw(address token, address payable receiver) public
    isAdmin
  {
    withdrawPlatform(token, receiver);
  }

  /*
   * Modifiers
   */

  modifier isLobby() {
    require(msg.sender == address(__lobby), 'LobbyContractOnly');
    _;
  }

  modifier hasRecord(uint gameId) {
    require(__games[gameId].exists, 'MissingRecord');
    _;
  }

  modifier isChallenge(uint gameId) {
    require(__games[gameId].state == GameState.Pending, 'InvalidContractState');
    _;
  }

  modifier inProgress(uint gameId) {
    require(__games[gameId].state == GameState.Started, 'InvalidContractState');
    _;
  }

  modifier inDraw(uint gameId) {
    require(__games[gameId].state == GameState.Draw, 'InvalidContractState');
    _;
  }

  modifier inReview(uint gameId) {
    GameData storage gameData = __games[gameId];
    require(gameData.state == GameState.Review, 'InvalidContractState');
    _;
  }

  modifier isFinished(uint gameId) {
    GameData storage gameData = __games[gameId];
    require(gameData.state == GameState.Finished, 'InvalidContractState');
    _;
  }

  modifier isCurrentMove(uint gameId) {
    require(__games[gameId].currentMove == msg.sender, 'NotCurrentMove');
    _;
  }

  modifier isOpponentsMove(uint gameId) {
    require(__games[gameId].currentMove == opponent(gameId), 'NotOpponentsMove');
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

  function isWhitePlayer(uint gameId) private view returns (bool) {
    return (msg.sender == __games[gameId].whitePlayer);
  }

  function isBlackPlayer(uint gameId) private view returns (bool) {
    return (msg.sender == __games[gameId].blackPlayer);
  }

  modifier isPlayer(uint gameId) {
    require(isWhitePlayer(gameId) || isBlackPlayer(gameId), 'PlayerOnly');
    _;
  }

  function opponent(uint gameId) public view
    isPlayer(gameId)
  returns (address) {
    GameData storage gameData = __games[gameId];
    return isWhitePlayer(gameId) ? gameData.blackPlayer : gameData.whitePlayer;
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
    require(timeDidExpire(gameId), 'TimerActive');
    _;
  }

  modifier timerActive(uint gameId) {
    require(!timeDidExpire(gameId), 'TimerExpired');
    _;
  }

  function balance(uint gameId, address player) public view
  returns (uint) {
    return escrow(player, gameId).amount;
  }

  function earnings(address token) public view
  returns (uint) {
    return earnings(msg.sender, token);
  }

  function withdraw(address token) public {
    withdraw(msg.sender, token);
  }

  function platformFeePerc() public view returns (uint) {
    return __platformFeePerc;
  }

  function platformFee(uint gameId) public view
  returns (uint) {
    uint fee = __games[gameId].wagerAmount * __platformFeePerc / 100;
    if (fee < __platformFeeMin) return __platformFeeMin;
    return fee;
  }

  function requiredBalance(uint gameId) private view
  returns (uint) {
    if (__games[gameId].state == GameState.Pending) {
      return __games[gameId].wagerAmount + platformFee(gameId);
    } else if (__games[gameId].state == GameState.Started) {
      return __games[gameId].wagerAmount;
    } else {
      return 0;
    }
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
  ) public payable
    isLobby
  returns (uint) {
    require(timePerMove >= 60, 'InvalidTimePerMove');
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
    if (wagerAmount > 0) {
      deposit(sender, gameId, wagerToken, wagerToken == address(0) ? msg.value : requiredBalance(gameId));
      require(escrow(sender, gameId).amount >= requiredBalance(gameId), 'InvalidDepositAmount');
    }
    return gameId;
  }

  function acceptChallenge(uint gameId) public payable
    isChallenge(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
  {
    GameData storage gameData = __games[gameId];
    if (gameData.wagerAmount > 0) {
      uint required = requiredBalance(gameId);
      deposit(msg.sender, gameId, gameData.wagerToken, gameData.wagerToken == address(0) ? msg.value : required);
      require(escrow(msg.sender, gameId).amount >= required, 'InvalidDepositAmount');
      uint wBal = escrow(gameData.whitePlayer, gameId).amount;
      if (wBal > required) refund(gameData.whitePlayer, gameId, wBal - required);
      uint bBal = escrow(gameData.blackPlayer, gameId).amount;
      if (bBal > required) refund(gameData.blackPlayer, gameId, bBal - required);
    }
    __lobby.acceptChallenge(gameId, msg.sender, opponent(gameId));
  }

  function declineChallenge(uint gameId) public
    isChallenge(gameId)
    isPlayer(gameId)
  {
    GameData storage gameData = __games[gameId];
    refund(gameData.whitePlayer, gameId);
    refund(gameData.blackPlayer, gameId);
    gameData.state = GameState.Declined;
    __lobby.cancelChallenge(gameId, msg.sender, opponent(gameId));
  }

  function modifyChallenge(
    uint gameId,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) public payable
    isChallenge(gameId)
    isPlayer(gameId)
  {
    require(timePerMove >= 60, 'InvalidTimePerMove');
    GameData storage gameData = __games[gameId];
    address receiver = opponent(gameId);
    if (startAsWhite && isBlackPlayer(gameId)
    || !startAsWhite && isWhitePlayer(gameId)) {
      address white = startAsWhite ? msg.sender : receiver;
      address black = startAsWhite ? receiver : msg.sender;
      gameData.whitePlayer = payable(white);
      gameData.blackPlayer = payable(black);
      gameData.currentMove = receiver;
    }
    if (timePerMove != gameData.timePerMove) {
      gameData.timePerMove = timePerMove;
    }
    if (wagerAmount != gameData.wagerAmount) {
      gameData.wagerAmount = wagerAmount;
      // Trim receiver's escrow if new wager is lower
      uint required = requiredBalance(gameId);
      uint recvBal = escrow(receiver, gameId).amount;
      if (recvBal > required) refund(receiver, gameId, recvBal - required);
    }
    if (gameData.wagerAmount > 0) {
      uint required = requiredBalance(gameId);
      address token = gameData.wagerToken;
      if (token == address(0)) {
        deposit(msg.sender, gameId, address(0), msg.value);
      } else {
        uint senderBal = escrow(msg.sender, gameId).amount;
        if (senderBal < required) deposit(msg.sender, gameId, token, required - senderBal);
      }
      require(escrow(msg.sender, gameId).amount >= required, 'InvalidDepositAmount');
    }
    __lobby.touch(gameId, msg.sender, receiver);
  }

  /*
   * Game Logic
   */

  function startGame(uint gameId) public
    isLobby
    isChallenge(gameId)
  {
    GameData storage gameData = __games[gameId];
    uint fee = platformFee(gameId);
    chargeFee(gameData.whitePlayer, gameId, gameData.wagerToken, fee);
    chargeFee(gameData.blackPlayer, gameId, gameData.wagerToken, fee);
    __bitboards[gameId].initialize();
    gameData.state = GameState.Started;
    gameData.currentMove = gameData.whitePlayer;
    gameData.timeOfLastMove = block.timestamp;
    emit GameStarted(gameId, gameData.whitePlayer, gameData.blackPlayer);
  }

  function _applyMove(uint gameId, string memory uci) private returns (GameOutcome) {
    (uint8 from, uint8 to, Piece promotion) = UCI.parse(uci);
    Color c = isWhitePlayer(gameId) ? Color.White : Color.Black;
    Piece captured = __bitboards[gameId].move(c, from, to, promotion);
    if (captured == Piece.King) {
      return c == Color.White ? GameOutcome.WhiteWon : GameOutcome.BlackWon;
    }
    return GameOutcome.Undecided;
  }

  function move(uint gameId, string memory uci) public
    inProgress(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    GameOutcome outcome = _applyMove(gameId, uci);
    __moves[gameId].push(uci);
    emit MoveSAN(gameId, msg.sender, uci);
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
    disburse(gameData.whitePlayer, gameData.blackPlayer, gameId, outcome);
    emit GameOver(gameId, winner(gameId), loser(gameId));
    __lobby.finishGame(gameId, outcome);
  }

  function resign(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
  {
    if (isWhitePlayer(gameId)) finishGame(gameId, GameOutcome.BlackWon);
    else finishGame(gameId, GameOutcome.WhiteWon);
  }

  function offerDraw(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    address receiver = opponent(gameId);
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Draw;
    gameData.currentMove = opponent(gameId);
    emit OfferedDraw(gameId, msg.sender, receiver);
    __lobby.touch(gameId, msg.sender, receiver);
  }

  function respondDraw(uint gameId, bool accept) external
    inDraw(gameId)
    isPlayer(gameId)
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
      gameData.currentMove = opponent(gameId);
      emit DeclinedDraw(gameId, msg.sender, receiver);
    }
  }

  function claimVictory(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
    isOpponentsMove(gameId)
    timerExpired(gameId)
  {
    finishGame(gameId, isWhitePlayer(gameId) ? GameOutcome.WhiteWon
                                             : GameOutcome.BlackWon);
  }

  function disputeGame(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
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
    __lobby.resolveDispute(gameId, gameData.whitePlayer, gameData.blackPlayer);
    finishGame(gameId, outcome);
    emit ArbiterAction(gameId, msg.sender, outcome);
  }
}
