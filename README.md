# The Blockchain Chess Lounge

## Client

The reference client uses the Nuxt3 framework.

*Start development server*

```
$ yarn dev
```

## Contracts

The *contracts/* directory contains the code for the smart contracts using [Foundry](https://github.com/foundry-rs/foundry).

*Start local blockchain*

```
$ anvil -m "$(cat .mnemonic)"
```

*Build and deploy the project*

```
$ forge build
$ forge script script/DeployLobby.s.sol --mnemonic-paths .mnemonic --sender <address> --fork-url http://localhost:8545 --broadcast
```
