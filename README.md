# The Blockchain Chess Lounge

## Client

The *client/* directory hold the code for the frontend.

## Contracts

The *contracts/* directory contains the code for the smart contracts.  We use [Foundry](https://github.com/foundry-rs/foundry) as a build tool.

### Local Development

*Start local blockchain*

```
$ anvil -m "$(cat .mnemonic)"
```

*Build and deploy the project*

```
$ forge build
$ forge script script/DeployLobby.s.sol --mnemonic-paths .mnemonic --sender <address> --fork-url http://localhost:8545 --broadcast
```
