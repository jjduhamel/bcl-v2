// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;
import './Lobby.sol';
import 'lib/stringUtils.sol';

contract ChessEngine is LobbyEvents {
  Lobby public immutable lobby;
  address public immutable arbiter;

  // Increments every time a new game (challenge) is created
  uint gameIndex;

  enum GameOutcome { Undecided, WhiteWon, BlackWon, Draw }
  enum GameState { Pending, Accepted, Declined, Started, Finished, Review }
  struct GameData {
    GameState state;
    GameOutcome outcome;
    // Game data
    address whitePlayer;
    address blackPlayer;
    address currentMove;
    //bool isWhiteMove;
    //string[] moves;
    // Time Per Move
    uint timePerMove;
    uint timeOfLastMove;
    // Wagering
    uint wagerAmount;
  }
  mapping(uint => GameData) private __games;
  // map gameId -> moves (san or [ from, to ])
  mapping(uint => string[]) __moves;
  //mapping(uint => bytes1[2][]) __moves;
  // map gameId -> fen
  mapping(uint => string) __fen;
  // map gameId -> player -> deposit amount
  mapping(uint => mapping(address => uint)) __deposits;

  function game(uint gameId) public view isGame(gameId) returns (GameData memory) {
    return __games[gameId];
  }

  function moves(uint gameId) public view isGame(gameId) returns (string[] memory) {
    return __moves[gameId];
  }

  modifier isLobby() {
    require(msg.sender == address(lobby), 'LobbyContractOnly');
    _;
  }

  function otherPlayer(uint gameId) private view isPlayer(gameId) returns (address) {
    GameData storage gameData = __games[gameId];
    return isWhitePlayer(gameId) ? gameData.blackPlayer : gameData.whitePlayer;
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

  function winner(uint gameId) public view isFinished(gameId) returns (address) {
    GameData storage gameData = __games[gameId];
    if (gameData.outcome == GameOutcome.WhiteWon) return gameData.whitePlayer;
    else if (gameData.outcome == GameOutcome.BlackWon) return gameData.blackPlayer;
    else return address(0);
  }

  function loser(uint gameId) public view isFinished(gameId) returns (address) {
    GameData storage gameData = __games[gameId];
    if (gameData.outcome == GameOutcome.WhiteWon) return gameData.blackPlayer;
    else if (gameData.outcome == GameOutcome.BlackWon) return gameData.whitePlayer;
    else return address(0);
  }

  modifier isCurrentMove(uint gameId) {
    require(__games[gameId].currentMove == msg.sender, 'NotCurrentMove');
    _;
  }

  modifier isOpponentsMove(uint gameId) {
    require(__games[gameId].currentMove == otherPlayer(gameId), 'NotOpponentsMove');
    _;
  }

  /*
   * Game State Modifiers
   */

  // FIXME
  modifier isGame(uint gameId) {
    require(__games[gameId].state, 'MissingRecord');
    _;
  }

  modifier isChallenge(uint gameId) {
    require(__games[gameId].state == GameState.Pending, 'InvalidContractState');
    _;
  }

  modifier isAccepted(uint gameId) {
    require(__games[gameId].state == GameState.Accepted, 'InvalidContractState');
    _;
  }

  modifier inProgress(uint gameId) {
    require(__games[gameId].state == GameState.Started, 'InvalidContractState');
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

  function timeDidExpire(uint gameId) public view returns (bool) {
    GameData storage gameData = __games[gameId];
    uint timeOfLastMove = gameData.timeOfLastMove;
    uint timePerMove = gameData.timeOfLastMove;
    if (timeOfLastMove == 0) return false;
    return block.timestamp > timeOfLastMove+timePerMove;
  }

  modifier timerExpired(uint gameId) {
    require(timeDidExpire(gameId), 'TimerStillActive');
    _;
  }

  modifier timerActive(uint gameId) {
    require(!timeDidExpire(gameId), 'TimerExpired');
    _;
  }

  constructor() {
    lobby = Lobby(msg.sender);
    arbiter = lobby.arbiter();
  }

  /*
   * Challenging Logic
   */

  function createChallenge(
    address player1,    // Player 1 is always who issues the challenge
    address player2,
    bool p1IsWhite,
    uint timePerMove,
    uint wagerAmount
  ) public payable isLobby returns (uint) {
    uint gameId = gameIndex++;
    address whitePlayer = p1IsWhite ? player1 : player2;
    address blackPlayer = p1IsWhite ? player2 : player1;
    // Initialize Game Data
    GameData memory gameData = GameData(
      GameState.Pending,
      GameOutcome.Undecided,
      whitePlayer,
      blackPlayer,
      player2,
      timePerMove,
      0,
      wagerAmount
    );
    // TODO: Wagering
    __games[gameId] = gameData;
    return gameId;
  }

  function acceptChallenge(uint gameId)
  public payable isChallenge(gameId) isCurrentMove(gameId) {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Accepted;
    gameData.currentMove = gameData.whitePlayer;
    lobby.startGame(gameId, gameData.whitePlayer, gameData.blackPlayer);
  }

  function declineChallenge(uint gameId)
  public isChallenge(gameId) isPlayer(gameId) {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Declined;
    lobby.cancelChallenge(gameId, msg.sender, otherPlayer(gameId));
  }

  // TODO Enforce contraints on TPM, wager, etc...
  function modifyChallenge(
    uint gameId,
    bool startAsWhite,
    uint timePerMove,
    uint wagerAmount
  ) public payable isChallenge(gameId) isPlayer(gameId) {
    GameData storage gameData = __games[gameId];
    address opponent = otherPlayer(gameId);
    gameData.whitePlayer = startAsWhite ? msg.sender : opponent;
    gameData.blackPlayer = startAsWhite ? opponent : msg.sender;
    gameData.currentMove = opponent;
    gameData.timePerMove = timePerMove;
    gameData.wagerAmount = wagerAmount;
    emit ModifiedChallenge(gameId, msg.sender, opponent);
  }

  /*
   * Game Logic
   */

  function startGame(uint gameId) public isLobby isAccepted(gameId) {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Started;
    gameData.currentMove = gameData.whitePlayer;
    gameData.timeOfLastMove = block.timestamp;
  }

  // TODO Reconcile payments
  function finishGame(uint gameId, GameOutcome outcome) private {
    GameData storage gameData = __games[gameId];
    gameData.state = GameState.Finished;
    gameData.outcome = outcome;
    lobby.finishGame(gameId, winner(gameId), loser(gameId));
  }

  function move(uint gameId, string memory san)
  //function move(uint gameId, bytes1 piece, bytes1 from, bytes1 to)
  public inProgress(gameId) isCurrentMove(gameId) timerActive(gameId) {
    GameData storage gameData = __games[gameId];
    // TODO Check if move is legal
    __moves[gameId].push(san);
    //__moves[gameId].push([ from, to ]);
    gameData.currentMove = otherPlayer(gameId);
    gameData.timeOfLastMove = block.timestamp;
    emit MoveSAN(gameId, msg.sender, san);
    lobby.broadcastMove(gameId, msg.sender, otherPlayer(gameId));
  }

  function resign(uint gameId) external inProgress(gameId) isPlayer(gameId) {
    GameData storage gameData = __games[gameId];
    if (isWhitePlayer(gameId)) finishGame(gameId, GameOutcome.BlackWon);
    else finishGame(gameId, GameOutcome.WhiteWon);
  }

  // TODO Needs tests
  function claimVictory(uint gameId)
  external inProgress(gameId) timerExpired(gameId) isOpponentsMove(gameId) {
    GameData storage gameData = __games[gameId];
    if (isWhitePlayer(gameId)) finishGame(gameId, GameOutcome.WhiteWon);
    else finishGame(gameId, GameOutcome.BlackWon);
  }

  /*
  function disputeOutcome(uint gameId) external isPlayer(gameId) inProgress(gameId) {
    state = GameState.Review;
    //Lobby(lobby).disputeGame(msg.sender, otherPlayer());
  }

  function resolveDispute(GameOutcome _outcome, address _winner, string memory comment)
  public inReview arbiterOnly {
    if (_outcome == GameOutcome.WhiteWon) {
      require(_winner == whitePlayer, 'AddressMismatch');
    } else if (_outcome == GameOutcome.BlackWon) {
      require(_winner == blackPlayer, 'AddressMismatch');
    }
    finish(_outcome);
    emit ArbiterAction(msg.sender, comment);
  }

  function resolveDispute(GameOutcome _outcome, address _winner)
  external inReview arbiterOnly {
    if (_outcome == GameOutcome.WhiteWon) resolve(_outcome, _winner, 'White won');
    else if (_outcome == GameOutcome.BlackWon) resolve(_outcome, _winner, 'Black won');
    else if (_outcome == GameOutcome.Draw) resolve(_outcome, _winner, 'Draw');
  }
  */
}
