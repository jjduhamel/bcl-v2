// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import '@forge/Test.sol';
import '@oz/token/ERC20/ERC20.sol';
import '../Challenge.t.sol';

contract MockToken is ERC20 {
  constructor() ERC20('Test Token', 'TST') {}
  function mint(address to, uint amount) external { _mint(to, amount); }
}

// Owner-funded ERC20 wager: deposits pull from the owner, payout releases the
// token to the winner's owner, and the agent key never holds tokens.
contract AgentGameERC20Test is ChallengeTest {
  MockToken token;
  address a1;  // owned by p1, seated white
  address a2;  // owned by p2, seated black
  uint gid;

  function setUp() public {
    token = new MockToken();
    token.mint(p1, 100 ether);
    token.mint(p2, 100 ether);
    a1 = makeAddr('agent1');
    a2 = makeAddr('agent2');

    // The opponent must be registered before it can be challenged (isRegistered(opponent)).
    changePrank(p2);
    lobby.registerAgent(a2, 'black-bot', '', '', '', '');
    token.approve(address(lobby), wager);
    lobby.deposit(wager, address(token));  // opponent pre-funds so the challenge-time balance check passes

    changePrank(p1);
    lobby.registerAgent(a1, 'white-bot', '', '', '', '');
    token.approve(address(lobby), wager);
    lobby.deposit(wager, address(token));  // challenger pre-funds too (_create checks both seats' balance)
    gid = lobby.challenge(a1, a2, true, timePerMove, wager, address(token));

    changePrank(p2);
    lobby.acceptChallenge(gid);
  }

  function testERC20PayoutToOwner() public {
    changePrank(a1);
    engine.move(gid, 'e2e4');
    changePrank(a2);
    engine.resign(gid);

    assertEq(engine.winner(gid), a1);

    changePrank(p1);
    assertEq(lobby.earnings(address(token)), purse());
    uint balBefore = token.balanceOf(p1);
    lobby.withdraw(address(token));
    assertEq(token.balanceOf(p1) - balBefore, purse());

    // The agent never custodies tokens.
    assertEq(token.balanceOf(a1), 0);
    assertEq(token.balanceOf(a2), 0);
  }
}
