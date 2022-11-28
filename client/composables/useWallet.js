import { ethers, BigNumber as BN } from 'ethers';
import WalletConnectProvider from '@walletconnect/ethereum-provider';
import useWalletStore from '../store/wallet';
const { Web3Provider } = ethers.providers;

export default async function() {
  const config = useRuntimeConfig();
  const wallet = useWalletStore();
  const walletConnectURI = ref(null);
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
  }

  function _disconnected() {
    console.log('Wallet disconnected');
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

  async function connectMetamask() {
    console.log('Connect metamask');
    wallet.source = 'metamask';
    wallet.connecting = true;
    provider = new Web3Provider(window.ethereum);
    await provider.send('eth_requestAccounts', []);
    await _connected();
  }

  async function connectWalletConnect() {
    console.log('Connect WalletConnect');
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

  return {
    wallet,
    provider,
    signer,
    fetchBalance,
    refreshBalance,
    connectMetamask,
    connectWalletConnect,
    walletConnectURI
  };
}
