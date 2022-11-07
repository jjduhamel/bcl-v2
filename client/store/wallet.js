import { ethers, providers } from 'ethers';
const { Web3Provider } = providers;

export default defineStore('wallet', {
  state: () => {
    return {
      installed: false,
      connected: false,
      address: null,
      network: null,
      balance: 0
    }
  },
  getters: {
    provider() {
      // TODO wallet connect
      return new Web3Provider(window.ethereum);
    },
    signer() {
      // TODO wallet connect
      return this.provider.getSigner();
    }
  }
});
