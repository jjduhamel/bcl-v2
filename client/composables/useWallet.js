import { ethers, providers } from 'ethers';
import WalletConnectProvider from '@walletconnect/web3-provider';
import { useWalletStore } from '../store/wallet';
const { Web3Provider } = providers;

export default function() {
  const wallet = useWalletStore();
  let metamask, walletConnect, signer;
  const walletConnectURI = ref(null);

  if (process.client && window.ethereum) {
    wallet.installed = true;
    metamask = new Web3Provider(window.ethereum);
  }

  async function _connected(provider) {
    const accounts = await provider.listAccounts();
    if (accounts.length == 0) throw new Error('No connected accounts');
    console.log('Wallet connected');
    signer = provider.getSigner();
    [ wallet.address, wallet.network, wallet.balance ] = await Promise.all([
      signer.getAddress(),
      provider.getNetwork().then(n => n.name),
      signer.getBalance().then(BigInt)
    ]);
    wallet.connected = true;
  }

  async function connectMetamask() {
    if (!wallet.installed) throw new Error('Metamask isn\'t installed');
    console.log('Connect metamask');
    await metamask.send('eth_requestAccounts', []);
    await _connected(metamask);
  }

  async function connectWalletConnect() {
    console.log('Connect WalletConnect');
    walletConnect = new WalletConnectProvider({
      infuraId: '2185ad08ea904e85b06c383c4cd6b902',
      qrcode: false
    });

    walletConnect.connector.on('display_uri', (err, data) => {
      walletConnectURI.value = data.params[0];
    });

    walletConnect.on('connect', (err, data) => {
      console.log('WalletConnect finished');
      const provider = new Web3Provider(walletConnect);
      _connected(provider);
    });

    walletConnect.on('disconnect', (err, data) => {
      console.log('WalletConnect disconnected');
      wallet.connected = false;
      wallet.address = null;
      wallet.network = null;
      wallet.balance = 0;
    });

    //walletConnect.on('accountsChanged', acctId => {});
    //walletConnect.on('chainChanged', acctId => {});

    walletConnect.enable();

    // Handle existing connection
    if (walletConnect.connected) {
      const provider = new Web3Provider(walletConnect);
      _connected(provider);
    }
  }

  return {
    wallet,
    metamask,
    connectMetamask,
    walletConnect,
    walletConnectURI,
    connectWalletConnect
  };
}
