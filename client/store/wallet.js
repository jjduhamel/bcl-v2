import { useStorage } from '@vueuse/core';
import { ethers, providers } from 'ethers';
const { Web3Provider } = providers;

export default defineStore('wallet', {
  state: () => {
    return {
      initialized: false,
      installed: false,
      connecting: false,
      connected: useStorage('bcl:wallet:connected', false),
      source: useStorage('bcl:wallet:source', null),
      address: null,
      network: null,
      balance: 0,
    };
  }
});
