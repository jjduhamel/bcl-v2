import { ethers, providers } from 'ethers';
import WalletConnectProvider from '@walletconnect/web3-provider';
import { useWalletStore } from '../store/wallet';
const { Web3Provider } = providers;

export default async function() {
  const wallet = useWalletStore();
  const walletConnectURI = ref(null);
  let provider, signer;

  if (window.ethereum) {
    wallet.installed = true;
    provider = new Web3Provider(window.ethereum);
    signer = provider.getSigner();
    if (!wallet.connected) {
      try {
        await _connected();
      } catch (err) {
        console.warn(err);
      }
    }
  }

  async function _connected() {
    const accounts = await provider.listAccounts();
    if (accounts.length == 0) throw new Error('No connected accounts');
    console.log('Wallet connected');
    [ wallet.address, wallet.network, wallet.balance ] = await Promise.all([
      signer.getAddress(),
      provider.getNetwork().then(n => n.name),
      signer.getBalance().then(BigInt)
    ]);
    //wallet.provider = provider;
    //wallet.signer = signer;
    //const addr = await wallet.provider.resolveName('xorax.eth');
    //console.log({ addr });
    wallet.connected = true;
  }

  async function connectMetamask() {
    if (!wallet.installed) throw new Error('Metamask isn\'t installed');
    console.log('Connect metamask');
    await provider.send('eth_requestAccounts', []);
    await _connected();
  }

  async function connectWalletConnect() {
    console.log('Connect WalletConnect');
    const walletConnect = new WalletConnectProvider({
      infuraId: '2185ad08ea904e85b06c383c4cd6b902',
      qrcode: false
    });

    walletConnect.connector.on('display_uri', (err, data) => {
      walletConnectURI.value = data.params[0];
    });

    walletConnect.on('connect', (err, data) => {
      console.log('WalletConnect finished');
      provider = new Web3Provider(walletConnect);
      _connected();
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
      provider = new Web3Provider(walletConnect);
      _connected();
    }
  }

  return {
    wallet,
    provider,
    signer,
    connectMetamask,
    connectWalletConnect,
    walletConnectURI
  };
}
