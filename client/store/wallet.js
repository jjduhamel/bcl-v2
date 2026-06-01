import { useStorage } from '@vueuse/core';
import { ethers, providers } from 'ethers';
const { Web3Provider } = providers;

export default defineStore('wallet', {
  state: () => {
    return {
      initialized: false,
      connected: useStorage('bcl:wallet:connected', false),
      source: useStorage('bcl:wallet:source', null),
      address: null,
      network: useStorage('bcl:wallet:network', 'sepolia'),
      chainId: useStorage('bcl:wallet:chainId', 11155111),
      balance: 0,
    };
  }
});
