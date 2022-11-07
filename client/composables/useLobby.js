import _ from 'lodash';
import { ethers, Contract } from 'ethers';
import LobbyContract from '../contracts/Lobby.sol/Lobby.json';
import EngineContract from '../contracts/ChessEngine.sol/ChessEngine.json';
import useLobbyStore from '../store/lobby';

export default async function() {
  const config = useRuntimeConfig();
  const { wallet, provider, signer } = await useWallet();

  const lobby = useLobbyStore();

  if (wallet.connected && !lobby.initialized) {
    await lobby.initialize();
  }

  const lobbyContract = lobby.contract;
  const chessEngine = gameId => lobby.engine(gameId);

  return {
    lobby,
    lobbyContract,
    chessEngine
  };
}
