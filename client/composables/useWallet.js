import { ethers, BigNumber as BN } from 'ethers';
import { formatEther } from 'ethers/lib/utils';
import WalletConnectProvider from '@walletconnect/ethereum-provider';
import useWalletStore from '../store/wallet';
const { Web3Provider } = ethers.providers;

export default async function() {
  const { $amplitude } = useNuxtApp();
  const config = useRuntimeConfig();
  const wallet = useWalletStore();
  let provider, signer;

  const walletConnect = new WalletConnectProvider({
    infuraId: config.infuraId,
    qrcode: false
  });

  if (window.ethereum) {
    wallet.installed = true;
  }

  if (wallet.source == 'walletconnect') {
    provider = new Web3Provider(walletConnect);
  } else if (wallet.source == 'metamask') {
    provider = new Web3Provider(window.ethereum);
  }

  if (!wallet.initialized) {
    await _initialize();
  } else if (wallet.connected) {
    signer = provider.getSigner();
  }

  async function _initialize() {
    console.log('Initialize wallet');
    wallet.initialized = true;
    if (wallet.connected) {
      wallet.connected = false;
      try {
        if (wallet.source == 'metamask') await connectMetamask();
        else if (wallet.source == 'walletconnect') await connectWalletConnect();
      } catch(err) {
        console.warn(err);
      }
    }
  }

  async function _connected() {
    const accounts = await provider.listAccounts();
    if (accounts.length == 0) throw new Error('No connected accounts');
    console.log('Wallet connected');
    signer = provider.getSigner();
    [ wallet.address, wallet.network, wallet.balance ] = await Promise.all([
      signer.getAddress(),
      provider.getNetwork().then(n => n.name),
      fetchBalance()
    ]);
    wallet.connecting = false;
    wallet.connected = true;

    // Initialize amplitude session
    await $amplitude.setUserId(wallet.address);
    await $amplitude.setGroup('network', wallet.network);
    await $amplitude.setGroup('source', wallet.source);
    $amplitude.track('WalletConnected');
  }

  function _disconnected() {
    console.log('Wallet disconnected');
    wallet.connected = false;
    wallet.source = null;
    wallet.address = null;
    wallet.network = null;
    wallet.balance = 0;
    $amplitude.track('WalletDisconnected');
    reset();
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

  async function connectMetamask() {
    console.log('Connect metamask');
    $amplitude.track('ConnectMetamask');
    wallet.source = 'metamask';
    wallet.connecting = true;
    provider = new Web3Provider(window.ethereum);
    await provider.send('eth_requestAccounts', []);
    await _connected();
  }

  const walletConnectURI = ref(null);
  async function connectWalletConnect() {
    console.log('Connect WalletConnect');
    $amplitude.track('ConnectWalletConnnect');
    wallet.source = 'walletconnect';
    wallet.connecting = true;

    walletConnect.connector.on('display_uri', (err, data) => {
      const uri = data.params[0];
      console.log('WalletConnect URI:', uri);
      walletConnectURI.value = uri;
    });

    walletConnect.on('disconnect', _disconnected);
    walletConnect.on('accountsChanged', _initialize);
    walletConnect.on('chainChanged', _initialize);

    await walletConnect.enable();

    if (walletConnect.connected) {
      provider = new Web3Provider(walletConnect);
      await _connected();
    }
  }

  async function disconnectWallet() {
    $amplitude.track('DisconnectWallet');
    if (!wallet.connected) throw Error('Wallet is not connected');
    console.log('Disconnect wallet');
    if (wallet.source == 'walletconnect') await walletConnnect.disconnect();
    _disconnected();
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
