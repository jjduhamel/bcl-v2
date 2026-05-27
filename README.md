# The Blockchain Chess Lounge

## Local Development

### Frontend

The reference client uses the Nuxt3 framework.

*Start development server*

```
$ yarn dev
```

### Contracts

The *contracts/* directory contains the code for the smart contracts using [Foundry](https://github.com/foundry-rs/foundry).

```
$ yarn devchain
$ yarn deploy:local
```

## Deployment

*Build and Deploy*

```
$ forge build
$ yarn deploy:app --sender <address> --rpc-url <rpc-url> --broadcast
```

*Upgrade ChessEngine Contract*

TODO
