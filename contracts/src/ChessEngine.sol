// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import '@lib/Bitboard.sol';
import './IChessEngine.sol';
import './Lobby.sol';

contract ChessEngine is Initializable, UUPSUpgradeable, IChessEngine {
  using Bitboard for Bitboard.Bitboard;
  using EnumerableMap for EnumerableMap.UintToUintMap;
  Lobby private __lobby;

  mapping(uint => GameData) private __games;
  // map gameId -> moves (san or [ from, to ])
  mapping(uint => string[]) __moves;
  // map gameId -> bitboards
  mapping(uint => Bitboard.Bitboard) __bitboards;
  // map player -> gameId -> deposit
  mapping(address => EnumerableMap.UintToUintMap) __escrow;
  // map player -> earnings
  mapping(address => uint) __earnings;

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
    require(__lobby.hasRole(__lobby.ADMIN_ROLE(), msg.sender), 'ArbiterOnly');
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

  function profit() public view
    isArbiter
  returns (uint) {
    return __earnings[address(0)];
  }

  function withdraw(address payable receiver) public
    isAdmin
  {
    receiver.transfer(profit());
    __earnings[address(0)] = 0;
  }

  function deposits(address player) public view
    isArbiter
  returns (uint[2][] memory) {
    EnumerableMap.UintToUintMap storage deposits = __escrow[player];
    uint[2][] memory out = new uint[2][](deposits.length());
    for (uint j=0; j<deposits.length(); j++) {
      (out[0][j],out[1][j]) = deposits.at(j);
    }
    return out;
  }

  function earnings(address player) public
    isArbiter
  returns (uint) {
    return __earnings[player];
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

  /*
   * Deposit, wager, platform fee
   */

  modifier deposit(uint gameId, address player)
  {
    // Update player deposit
    if (msg.value > 0) {
      uint deposit = balance(gameId, player);
      __escrow[player].set(gameId, deposit+msg.value);
    }
    _;
    // Check the player has enough left over after tx
    if (__games[gameId].wagerAmount > 0) {
      require(balance(gameId, player) >= requiredBalance(gameId)
             , 'InvalidDepositAmount');
    }
  }

  function deposits() public view
  returns (uint[2][] memory) {
    EnumerableMap.UintToUintMap storage deposits = __escrow[msg.sender];
    uint[2][] memory out = new uint[2][](deposits.length());
    for (uint j=0; j<deposits.length(); j++) {
      (out[0][j],out[1][j]) = deposits.at(j);
    }
    return out;
  }

  function balance(uint gameId, address player) public view
  returns (uint) {
    (bool exists, uint deposit) = __escrow[player].tryGet(gameId);
    return exists ? deposit : 0;
  }

  function earnings() public returns (uint) {
    return __earnings[msg.sender];
  }

  function withdraw() public {
    uint balance = __earnings[msg.sender];
    payable(msg.sender).transfer(balance);
    __earnings[msg.sender] = 0;
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

  function chargePlatformFee(uint gameId, address player) private {
    if (__games[gameId].wagerAmount == 0) return;
    uint deposit = balance(gameId, player);
    uint fee = platformFee(gameId);
    require(deposit >= fee, 'InvalidDepositAmount');
    __escrow[player].set(gameId, deposit-fee);
    __earnings[address(0)] += fee;
  }

  function refundExcess(uint gameId, address payable player) private
    isChallenge(gameId)
  {
    uint required = requiredBalance(gameId);
    uint deposit = balance(gameId, player);
    if (deposit > required) {
      __earnings[player] += deposit-required;
      __escrow[player].set(gameId, required);
    }
  }

  function refund(uint gameId, address payable player) private
    isChallenge(gameId)
  {
    uint deposit = balance(gameId, player);
    __earnings[player] = deposit;
    __escrow[player].remove(gameId);
  }

  function disburse(uint gameId) private
    isFinished(gameId)
  {
    GameData storage gameData = __games[gameId];
    uint wDeposit = balance(gameId, gameData.whitePlayer);
    uint bDeposit = balance(gameId, gameData.blackPlayer);
    __escrow[gameData.whitePlayer].remove(gameId);
    __escrow[gameData.blackPlayer].remove(gameId);
    if (gameData.outcome == GameOutcome.WhiteWon) {
      __earnings[gameData.whitePlayer] += wDeposit+bDeposit;
    } else if (gameData.outcome == GameOutcome.BlackWon) {
      __earnings[gameData.blackPlayer] += wDeposit+bDeposit;
    } else if (gameData.outcome == GameOutcome.Draw) {
      __earnings[gameData.whitePlayer] += wDeposit;
      __earnings[gameData.blackPlayer] += bDeposit;
    } else {
      revert('InvalidGameOutcome');
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
    uint wagerAmount
  ) public payable
    isLobby
    deposit(gameId, sender)
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
      wagerAmount
    );
    return gameId;
  }

  function acceptChallenge(uint gameId) public payable
    isChallenge(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    deposit(gameId, msg.sender)
  {
    GameData storage gameData = __games[gameId];
    refundExcess(gameId, gameData.whitePlayer);
    refundExcess(gameId, gameData.blackPlayer);
    __lobby.acceptChallenge(gameId, msg.sender, opponent(gameId));
  }

  function declineChallenge(uint gameId) public
    isChallenge(gameId)
    isPlayer(gameId)
  {
    GameData storage gameData = __games[gameId];
    refund(gameId, gameData.whitePlayer);
    refund(gameId, gameData.blackPlayer);
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
    deposit(gameId, msg.sender)
  {
    require(timePerMove >= 60, 'InvalidTimePerMove');
    GameData storage gameData = __games[gameId];
    address receiver = opponent(gameId);
    address white = startAsWhite ? msg.sender : receiver;
    address black = startAsWhite ? receiver : msg.sender;
    gameData.whitePlayer = payable(white);
    gameData.blackPlayer = payable(black);
    gameData.currentMove = receiver;
    gameData.timePerMove = timePerMove;
    gameData.wagerAmount = wagerAmount;
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
    chargePlatformFee(gameId, gameData.whitePlayer);
    chargePlatformFee(gameId, gameData.blackPlayer);
    __bitboards[gameId].initialize();
    gameData.state = GameState.Started;
    gameData.currentMove = gameData.whitePlayer;
    gameData.timeOfLastMove = block.timestamp;
    emit GameStarted(gameId, gameData.whitePlayer, gameData.blackPlayer);
  }

  //function move(uint gameId, bytes1 piece, bytes1 from, bytes1 to) public
  function move(uint gameId, string memory san) public
    inProgress(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    GameData storage gameData = __games[gameId];
    // TODO Check if move is legal
    __moves[gameId].push(san);
    //__moves[gameId].push([ from, to ]);
    gameData.currentMove = opponent(gameId);
    gameData.timeOfLastMove = block.timestamp;
    emit MoveSAN(gameId, msg.sender, san);
    __lobby.touch(gameId, msg.sender, opponent(gameId));
  }

  function finishGame(uint gameId, GameOutcome outcome) private {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Finished;
    gameData.outcome = outcome;
    disburse(gameId);
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
