import { useStorage } from '@vueuse/core';
import { ethers, providers } from 'ethers';
const { Web3Provider } = providers;

export default defineStore('wallet', {
  state: () => {
    return {
      initialized: false,
      connected: false,
      //connected: useStorage('bcl:wallet:connected', false),
      source: useStorage('bcl:wallet:source', null),
      //source: useStorage('bcl:wallet:source', null),
      address: null,
      network: null,
      chainId: null,
      balance: 0,
    };
  }
});
