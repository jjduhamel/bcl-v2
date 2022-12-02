export default defineNuxtRouteMiddleware(async (to, from) => {
  const { wallet } = await useWallet();
  if (!wallet.connected) return navigateTo('/landing');
});


