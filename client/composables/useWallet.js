import { BigNumber as BN } from 'ethers';
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
import { formatEther } from 'ethers/lib/utils';
import useWalletStore from '../store/wallet';

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
  autoConnect: true,
  provider,
  webSocketProvider
});

export default async function() {
  const { $amplitude } = useNuxtApp();
  const wallet = useWalletStore();
  let signer;

  try {
    if (!wallet.initialized) {
      console.log('Initialize wallet using', wallet.source);
      if (wallet.source == 'walletconnect') await connectWalletConnect();
      else if (wallet.source == 'metamask') await connectMetamask();
      wallet.initialized = true;
    } else {
      await _connected();
    }
  } catch (err) {
    console.warn(err);
  }

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
    const bal = await fetchBalance();
    return BN.from(bal.value).toString();
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

  async function connectMetamask() {
    console.log('Connect metamask');
    wallet.connecting = true;
    wallet.source = 'metamask';
    await connect({
      connector: new MetaMaskConnector()
    });
    wallet.connecting = false;
    await _connected();
    registerEventListeners();
  }

  const walletConnectURI = ref(null);
  async function connectWalletConnect() {
    console.log('Connect WalletConnect');
    $amplitude.track('ConnectWalletConnnect');
    wallet.connecting = true;
    wallet.source = 'walletconnect';

    const connector = new WalletConnectConnector({
      options: {
        qrcode: false
      }
    });

    connector.on('message', async msg => {
      const wc = await connector.getProvider();
      walletConnectURI.value = wc.connector.uri;
    });

    await connect({ connector });
    await _connected();
    registerEventListeners();
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
    provider,
    signer,
    currentNetwork,
    currentBalance,
    fetchBalance,
    refreshBalance,
    connectMetamask,
    walletConnectURI,
    connectWalletConnect,
    disconnectWallet
  };
}
