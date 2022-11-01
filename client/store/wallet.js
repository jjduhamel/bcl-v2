import { defineStore } from 'pinia';

export const useWalletStore = defineStore('wallet', {
  state: () => {
    return {
      installed: false,
      connected: false,
      address: null,
      network: null,
      balance: 0
    }
  }
});
