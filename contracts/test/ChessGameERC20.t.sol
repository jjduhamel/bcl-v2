// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@forge/console2.sol';
import '@oz/token/ERC20/ERC20.sol';
import './Challenge.t.sol';

contract MockERC20 is ERC20 {
  constructor() ERC20('Test Token', 'TST') {}
  function mint(address to, uint amount) external { _mint(to, amount); }
}

abstract contract ERC20ChallengeTest is ChallengeTest {
  MockERC20 token;

  function setUp() public virtual {
    token = new MockERC20();
    token.mint(p1, 100 ether);
    token.mint(p2, 100 ether);

    changePrank(p1);
    token.approve(address(engine), deposit);
    gameId = lobby.challenge(p2, true, timePerMove, wager, address(token));
    changePrank(p2);
  }

  function _move(address player, string memory uci) internal {
    changePrank(player);
    engine.move(gameId, uci);
  }
}

contract ERC20DeclineChallengeTest is ERC20ChallengeTest {
  function testDeclineRefundsToEarnings() public {
    engine.declineChallenge(gameId);
    changePrank(p1);
    assertEq(engine.earnings(address(token)), deposit);
  }

  function testWithdrawERC20AfterDecline() public {
    engine.declineChallenge(gameId);
    changePrank(p1);
    uint balBefore = token.balanceOf(p1);
    engine.withdraw(address(token));
    assertEq(token.balanceOf(p1) - balBefore, deposit);
    assertEq(engine.earnings(address(token)), 0);
  }
}

contract ERC20GameTest is ERC20ChallengeTest {
  function setUp() public override {
    super.setUp();
    token.approve(address(engine), deposit);
    engine.acceptChallenge(gameId);
    changePrank(p2);
  }

  function testWagerTokenStoredInGameData() public {
    GameData memory gameData = engine.game(gameId);
    assertEq(gameData.wagerToken, address(token));
    assertEq(gameData.wagerAmount, wager);
  }

  function testERC20PayoutOnResign() public {
    changePrank(p1);
    engine.resign(gameId);
    changePrank(p2);
    uint balBefore = token.balanceOf(p2);
    engine.withdraw(address(token));
    assertEq(token.balanceOf(p2) - balBefore, 2 * wager);
    assertEq(engine.earnings(address(token)), 0);
  }

  function testPlatformFeeInERC20() public {
    _move(p1, 'f2f3');
    _move(p2, 'e7e5');
    _move(p1, 'g2g4');
    _move(p2, 'd8h4');
    _move(p1, 'a2a3');
    _move(p2, 'h4e1');
    changePrank(arbiter);
    assertEq(engine.profit(address(token)), 2 * fee);
    address receiver = makeAddr('feeReceiver');
    uint balBefore = token.balanceOf(receiver);
    engine.withdraw(address(token), payable(receiver));
    assertEq(token.balanceOf(receiver) - balBefore, 2 * fee);
    assertEq(engine.profit(address(token)), 0);
  }
}
