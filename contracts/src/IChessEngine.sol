// SPDX-License-Identifier: GPL-V3
pragma solidity >=0.4.22 <0.9.0;

interface IChessEngine {
  enum GameState { Pending, Started, Draw, Finished, Review, Migrated }
  enum GameOutcome { Undecided, Declined, WhiteWon, BlackWon, Draw }

  struct GameData {
    bool exists;
    GameState state;
    GameOutcome outcome;
    // Game data
    address payable whitePlayer;
    address payable blackPlayer;
    address currentMove;
    // Time Per Move
    uint timePerMove;
    uint timeOfLastMove;
    // Wagering
    uint wagerAmount;
    //address wagerToken;
  }

  event GameStarted(uint indexed gameId
                  , address indexed whitePlayer
                  , address indexed blackPlayer);
  event GameOver(uint indexed gameId
               , GameOutcome indexed outcome
               , address indexed winner);
  event PlayerMoved(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event MoveSAN(uint indexed gameId
              , address indexed player
              , string san);
  event OfferedDraw(uint indexed gameId
                  , address indexed sender
                  , address indexed receiver);
  event AcceptedDraw(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event DeclinedDraw(uint indexed gameId
                   , address indexed sender
                   , address indexed receiver);
  event ArbiterAction(uint indexed gameId
                    , address indexed arbiter
                    , GameOutcome indexed outcome);
}
