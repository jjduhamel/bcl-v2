export default defineNuxtRouteMiddleware(async (to, from) => {
  const { wallet } = await useWallet();
  watch(() => wallet.connected, async isConnected => {
    if (!isConnected) {
      console.log('Wallet was disconnected, redirecting...');
      await navigateTo('/landing');
    }
  });
  if (!wallet.connected) return navigateTo('/landing');
});
