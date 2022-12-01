import { ethers, BigNumber as BN } from 'ethers';
import {
  createClient,
  configureChains,
  chain,
  connect,
  disconnect,
  fetchSigner,
  getProvider,
  getAccount,
  getNetwork,
  fetchBalance,
  watchAccount,
  watchNetwork,
} from '@wagmi/core';
import { publicProvider } from '@wagmi/core/providers/public';
import { infuraProvider } from '@wagmi/core/providers/infura';
import { alchemyProvider } from '@wagmi/core/providers/alchemy';
import { MetaMaskConnector } from '@wagmi/core/connectors/metaMask';
import { WalletConnectConnector } from '@wagmi/core/connectors/walletConnect';
import { CoinbaseWalletConnector } from '@wagmi/core/connectors/coinbaseWallet';
import { formatEther } from 'ethers/lib/utils';
import useWalletStore from '../store/wallet';
const { Web3Provider } = ethers.providers;

const config = useRuntimeConfig();

const { chains, provider, webSocketProvider } = configureChains(
  [ chain.mainnet
  , chain.polygon
  , chain.goerli
  , chain.polygonMumbai ],
  //[ alchemyProvider({ apiKey: config.alchemyId })
  [ infuraProvider({ apiKey: config.infuraId })
  , publicProvider() ]
);

const wagmi = createClient({
  //autoConnect: true,
  provider,
  webSocketProvider
});

export default async function() {
  const { $amplitude } = useNuxtApp();
  const wallet = useWalletStore();
  let signer;

  function initWalletConnect() {
    return new WalletConnectProvider({
      infuraId: config.infuraId,
      qrcode: false
    });
  }

  function initCoinbaseWallet() {
    return new CoinbaseWalletSDK({
      appName: 'Chessloun.ge',
      headlessMode: true
    });
  }

  try {
    if (wallet.connected) {
      if (!wallet.initialized) {
        console.log('Initialize wallet using', wallet.source);
        if (wallet.source == 'walletconnect') await connectWalletConnect();
        else if (wallet.source == 'metamask') await connectMetamask();
      } else {
        await _connected();
      }
    }
  } catch (err) {
    wallet.connected = false;
    console.warn(err);
  }
  wallet.initialized = true;

  async function _connected() {
    const { address, isConnected } = getAccount();
    const net = getNetwork();
    if (!isConnected) throw Error('Wallet wasn\'t connected');
    signer = await fetchSigner();
    wallet.address = address;
    wallet.network = net.chain.network;
    wallet.chainId = net.chain.id;
    wallet.connected = true;
    // Initialize amplitude session
    await $amplitude.setUserId(wallet.address);
    await $amplitude.setGroup('network', wallet.network);
    await $amplitude.setGroup('source', wallet.source);
    $amplitude.track('WalletConnected');
  }

  function _disconnected() {
    console.log('Wallet disconnected');
    $amplitude.track('WalletDisconnected');
    wallet.connected = false;
    wallet.source = null;
    wallet.address = null;
    wallet.network = null;
    wallet.balance = 0;
  }

  async function fetchBalance() {
    const bal = await signer.getBalance();
    return BN.from(bal).toString();
  }

  async function refreshBalance() {
    wallet.balance = await fetchBalance();
  }

  const currentBalance = computed(() => {
    // TODO Native token
    return `${(+formatEther(wallet.balance)).toFixed(3)} ETH`;
  });

  const currentNetwork = computed(() => {
    switch (wallet.network) {
      case 'homestead': return 'Ethereum';
      case 'goerli': return 'Goerli';
      case 'matic': return 'Polygon';
      case 'maticmum': return 'Mumbai';
      default: return wallet.network;
    }
  });

  async function switchNetwork(chainId) {
    console.log('Switch to network', chainId);
    /*
    if (wallet.source == 'walletconnect') {
      // TODO
    } else if (wallet.source == 'coinbase') {
      const cbProvider = coinbaseWallet.makeWeb3Provider();
      await cbProvider.switchEthereumChain(80001);
    } else if (wallet.source == 'metamask') {
      await provider.send('wallet_switchEthereumChain', [{ chainId }]);
    }
    */
  }

  async function connectMetamask() {
    console.log('Connect metamask');
    wallet.source = 'metamask';
    await connect({
      connector: new MetaMaskConnector()
    });
    await _connected();
    registerEventListeners();
  }

  async function connectWalletConnect() {
    return new Promise(async (resolve, reject) => {
      console.log('Connect WalletConnect');
      $amplitude.track('ConnectWalletConnnect');
      wallet.source = 'walletconnect';

      const connector = new WalletConnectConnector({
        options: {
          qrcode: false
        }
      });

      connector.on('message', async msg => {
        const wc = await connector.getProvider();
        resolve(wc.connector.uri);
      });

      setTimeout(() => reject('WalletConnect timed out'), 10000);
      await connect({ connector });
      await _connected();
      registerEventListeners();
    });
  }

  async function connectCoinbaseWallet() {
    return new Promise(async (resolve, reject) => {
      console.log('Connect Coinbase Wallet');
      $amplitude.track('ConnectCoinbaseWallet');
      wallet.source = 'coinbase';
      const connector = new CoinbaseWalletConnector({
         options: {
            appName: 'Chessloun.ge',
            headlessMode: true
          },
      });
      const cb = await connector.getProvider();
      resolve(cb.qrUrl);
      await connect({ connector });
      await _connected();
      registerEventListeners();
    });
  }

  async function disconnectWallet() {
    $amplitude.track('DisconnectWallet');
    if (!wallet.connected) throw Error('Wallet is not connected');
    console.log('Disconnect wallet');
    await disconnect();
  }

  function registerEventListeners() {
    console.log('Listen for wallet events');

    const unsubAcct = watchAccount(acct => {
      const { address, isConnected } = acct;
      console.log('Account changed', wallet.address, '->', address);
      $amplitude.track('AccountChanged');
      if (isConnected) wallet.address = address;
      else {
        _disconnected();
        navigateTo('/landing');
      }
    });

    const unsubNetwork = watchNetwork(net => {
      if (net.chain) {
        const { network, chainId } = net.chain;
        console.log('Network changed', wallet.network, `[${wallet.chainId}] ->`, network, `[]${chainId}`);
        $amplitude.track('NetworkChanged');
        _connected();
      }
    });

    // Unsub all events
    return () => _.each([
      unsubAcct,
      unsubNetwork
    ], f => f());;
  }

  return {
    wallet,
    //provider,
    signer,
    currentNetwork,
    currentBalance,
    fetchBalance,
    refreshBalance,
    switchNetwork,
    connectMetamask,
    connectWalletConnect,
    connectCoinbaseWallet,
    disconnectWallet,
    registerEventListeners,
  };
}
