// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import '@oz-upgradeable/proxy/utils/Initializable.sol';
import '@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@oz/utils/structs/EnumerableMap.sol';
import './IChessEngine.sol';
import './Lobby.sol';

contract ChessEngine is Initializable, UUPSUpgradeable, IChessEngine {
  using EnumerableMap for EnumerableMap.UintToUintMap;
  Lobby private __lobby;

  mapping(uint => GameData) private __games;
  // map gameId -> moves (san or [ from, to ])
  mapping(uint => string[]) __moves;
  // map gameId -> bitboards
  mapping(uint => bytes8[6]) __bitboards;
  // map player -> gameId -> deposit[]
  mapping(address => EnumerableMap.UintToUintMap) __deposits;

  // Platform fees
  uint __platformFeePerc;
  uint __platformFeeMin;
  uint __houseBalance;

  constructor() {
    _disableInitializers();
  }

  function initialize(address lobby) public initializer {
    __UUPSUpgradeable_init();
    __lobby = Lobby(lobby);
    // Initialize platform fees;
    __houseBalance = 0;
    __platformFeePerc = 1;
    __platformFeeMin = 0;
  }

  function _authorizeUpgrade(address newImplementation) internal override
    isArbiter
  {}

  modifier isLobby() {
    require(msg.sender == address(__lobby), 'LobbyContractOnly');
    _;
  }

  modifier isArbiter() {
    require(__lobby.hasRole(__lobby.ARBITER_ROLE(), msg.sender), 'ArbiterOnly');
    _;
  }

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

  /*
   * Game State Modifiers
   */

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

  /*
   * Game Clock Modifiers
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

  modifier addFunds(uint gameId, address player) {
    if (msg.value > 0) {
      uint deposit = playerBalance(gameId, player);
      __deposits[player].set(gameId, deposit+msg.value);
    }
    _;
  }

  modifier isFunded(uint gameId, address player)
  {
    _;
    GameData storage gameData = __games[gameId];
    if (gameData.wagerAmount > 0) {
      uint deposit = playerBalance(gameId, player);
      uint requiredAmount = gameData.wagerAmount;
      if (gameData.state == GameState.Pending) {
        requiredAmount += platformFee(gameId);
      }
      require(deposit >= requiredAmount, 'InvalidDepositAmount');
    }
  }

  function playerBalance(uint gameId, address player) public view
  returns (uint) {
    (bool exists, uint deposit) = __deposits[player].tryGet(gameId);
    return exists ? deposit : 0;
  }

  function balance(uint gameId) public view
    isPlayer(gameId)
  returns (uint) {
    return playerBalance(gameId, msg.sender);
  }

  function platformFeePerc() public view
  returns (uint) {
    return __platformFeePerc;
  }

  function platformFee(uint gameId) public view
  returns (uint) {
    GameData storage gameData = __games[gameId];
    uint wagerAmount = gameData.wagerAmount;
    uint fee = wagerAmount * __platformFeePerc / 100;
    if (fee < __platformFeeMin) return __platformFeeMin;
    return fee;
  }

  function chargePlatformFee(uint gameId, address player) private {
    GameData storage gameData = __games[gameId];
    if (gameData.wagerAmount == 0) return;
    uint deposit = playerBalance(gameId, player);
    uint fee = platformFee(gameId);
    require(deposit >= fee, 'InvalidDepositAmount');
    __deposits[player].set(gameId, deposit-fee);
    __houseBalance += fee;
  }

  modifier chargePlatformFees(uint gameId) {
    GameData storage gameData = __games[gameId];
    chargePlatformFee(gameId, gameData.whitePlayer);
    chargePlatformFee(gameId, gameData.blackPlayer);
    _;
  }

  function disburseExcessFunds(uint gameId, address payable player) private
    inProgress(gameId)
  {
    GameData storage gameData = __games[gameId];
    uint wagerAmount = gameData.wagerAmount;
    uint deposit = playerBalance(gameId, player);
    if (deposit > wagerAmount) {
      player.transfer(deposit - wagerAmount);
      __deposits[player].set(gameId, wagerAmount);
    }
  }

  function disburseExcessFunds(uint gameId) private
    inProgress(gameId)
  {
    GameData storage gameData = __games[gameId];
    disburseExcessFunds(gameId, gameData.whitePlayer);
    disburseExcessFunds(gameId, gameData.blackPlayer);
  }

  function disburseFunds(uint gameId) private
    isFinished(gameId)
  {
    GameData storage gameData = __games[gameId];
    uint wDeposit = playerBalance(gameId, gameData.whitePlayer);
    uint bDeposit = playerBalance(gameId, gameData.blackPlayer);

    if (gameData.outcome == GameOutcome.WhiteWon) {
      gameData.whitePlayer.transfer(wDeposit + bDeposit);
    } else if (gameData.outcome == GameOutcome.BlackWon) {
      gameData.blackPlayer.transfer(wDeposit + bDeposit);
    } else if (gameData.outcome == GameOutcome.Declined ||
               gameData.outcome == GameOutcome.Draw) {
      gameData.whitePlayer.transfer(wDeposit);
      gameData.blackPlayer.transfer(bDeposit);
    } else {
      revert('InvalidGameOutcome');
    }

    __deposits[gameData.whitePlayer].remove(gameId);
    __deposits[gameData.blackPlayer].remove(gameId);
  }

  function runningBalance() public view
    isArbiter
  returns (uint) {
    return __houseBalance;
  }

  function withdrawRunningBalance(address payable receiver) public
    isArbiter
  {
    receiver.transfer(__houseBalance);
    __houseBalance = 0;
  }

  function setPlatformFee(uint perc) public
    isArbiter
  { __platformFeePerc = perc; }

  function setMinPlatformFee(uint amount) public
    isArbiter
  { __platformFeeMin = amount; }

  /*
   * Game Logic
   */

  function isWhitePlayer(uint gameId) private view returns (bool) {
    return (msg.sender == __games[gameId].whitePlayer);
  }

  function isBlackPlayer(uint gameId) private view returns (bool) {
    return (msg.sender == __games[gameId].blackPlayer);
  }

  function isEitherColor(uint gameId) private view returns (bool) {
    return (isWhitePlayer(gameId) || isBlackPlayer(gameId));
  }

  modifier isPlayer(uint gameId) {
    require(isEitherColor(gameId), 'PlayerOnly');
    _;
  }

  function otherPlayer(uint gameId) private view
    isPlayer(gameId)
  returns (address) {
    GameData storage gameData = __games[gameId];
    return isWhitePlayer(gameId) ? gameData.blackPlayer : gameData.whitePlayer;
  }

  modifier isCurrentMove(uint gameId) {
    require(__games[gameId].currentMove == msg.sender, 'NotCurrentMove');
    _;
  }

  modifier isOpponentsMove(uint gameId) {
    require(__games[gameId].currentMove == otherPlayer(gameId), 'NotOpponentsMove');
    _;
  }

  function checkTPM(uint tpm) private pure {
    require(tpm >= 60, 'InvalidTimePerMove');
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
   * Challenging Logic
   */

  function createChallenge(
    uint gameId,
    address sender,
    address receiver,
    address whitePlayer,
    address blackPlayer,
    uint timePerMove,
    uint wagerAmount
  ) public payable
    isLobby
    addFunds(gameId, sender)
    isFunded(gameId, sender)
    returns (uint)
  {
    checkTPM(timePerMove);
    __games[gameId] = GameData(
      true,
      GameState.Pending,
      GameOutcome.Undecided,
      payable(whitePlayer),
      payable(blackPlayer),
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
    addFunds(gameId, msg.sender)
    isFunded(gameId, msg.sender)
  {
    __lobby.acceptChallenge(gameId, msg.sender, otherPlayer(gameId));
  }

  function declineChallenge(uint gameId) public
    isChallenge(gameId)
    isPlayer(gameId)
  {
    finishGame(gameId, GameOutcome.Declined);
    __lobby.cancelChallenge(gameId, msg.sender, otherPlayer(gameId));
  }

  function modifyChallenge(
    uint gameId,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) public payable
    isChallenge(gameId)
    isPlayer(gameId)
    addFunds(gameId, msg.sender)
    isFunded(gameId, msg.sender)
  {
    checkTPM(timePerMove);
    GameData storage gameData = __games[gameId];
    address opponent = otherPlayer(gameId);
    address whitePlayer = startAsWhite ? msg.sender : opponent;
    address blackPlayer = startAsWhite ? opponent : msg.sender;
    gameData.whitePlayer = payable(whitePlayer);
    gameData.blackPlayer = payable(blackPlayer);
    gameData.currentMove = opponent;
    gameData.timePerMove = timePerMove;
    gameData.wagerAmount = wagerAmount;
    __lobby.touch(gameId, msg.sender, opponent);
  }

  /*
   * Game Logic
   */

  function startGame(uint gameId) public
    isLobby
    isChallenge(gameId)
    chargePlatformFees(gameId)
  {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Started;
    gameData.currentMove = gameData.whitePlayer;
    gameData.timeOfLastMove = block.timestamp;
    disburseExcessFunds(gameId);
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
    gameData.currentMove = otherPlayer(gameId);
    gameData.timeOfLastMove = block.timestamp;
    emit MoveSAN(gameId, msg.sender, san);
    __lobby.touch(gameId, msg.sender, otherPlayer(gameId));
  }

  function finishGame(uint gameId, GameOutcome outcome) private {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Finished;
    gameData.outcome = outcome;
    disburseFunds(gameId);
    emit GameOver(gameId, outcome, winner(gameId));
  }

  function resign(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
  {
    if (isWhitePlayer(gameId)) finishGame(gameId, GameOutcome.BlackWon);
    else finishGame(gameId, GameOutcome.WhiteWon);
    __lobby.finishGame(gameId, msg.sender, otherPlayer(gameId));
  }

  function offerDraw(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    address opponent = otherPlayer(gameId);
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Draw;
    gameData.currentMove = otherPlayer(gameId);
    emit OfferedDraw(gameId, msg.sender, opponent);
    __lobby.touch(gameId, msg.sender, opponent);
  }

  function respondDraw(uint gameId, bool accept) external
    inDraw(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
    timerActive(gameId)
  {
    address opponent = otherPlayer(gameId);
    GameData storage gameData = __games[gameId];
    if (accept) {
      emit AcceptedDraw(gameId, msg.sender, opponent);
      finishGame(gameId, GameOutcome.Draw);
      __lobby.finishGame(gameId, msg.sender, opponent);
    } else {
      gameData.state = GameState.Started;
      gameData.currentMove = otherPlayer(gameId);
      emit DeclinedDraw(gameId, msg.sender, opponent);
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
    __lobby.finishGame(gameId, msg.sender, otherPlayer(gameId));
  }

  function disputeGame(uint gameId) external
    inProgress(gameId)
    isPlayer(gameId)
    isCurrentMove(gameId)
  {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Review;
    __lobby.disputeGame(gameId, msg.sender, otherPlayer(gameId));
  }

  function resolveDispute(uint gameId, GameOutcome outcome) external
    inReview(gameId)
    isArbiter
  {
    GameData storage gameData = __games[gameId];
    finishGame(gameId, outcome);
    __lobby.resolveDispute(gameId, gameData.whitePlayer, gameData.blackPlayer);
    __lobby.finishGame(gameId, gameData.whitePlayer, gameData.blackPlayer);
    emit ArbiterAction(gameId, msg.sender, outcome);
  }
}
