// https://nuxt.com/docs/api/configuration/nuxt-config
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineNuxtConfig({
  srcDir: 'client/',
  ssr: false,
  css: [ '@/assets/styles/tailwind.css' ],
  app: {
    head: {
      title: 'Chessloun.ge',
      link: [{ rel: 'icon', type: 'image/x-icon', href: '/favicon.ico?v1' }]
    }
  },
  modules: [
    [ '@pinia/nuxt',
      { autoImports: [ 'defineStore' ] }
    ],
    '@nuxtjs/tailwindcss',
    '@vueuse/nuxt',
    //'@nuxt/content',
  ],
  runtimeConfig: {
    public: {
      amplitudeId: process.env.AMPLITUDE_API_KEY,
      bugsnagId: process.env.BUGSNAG_API_KEY,
      infuraId: process.env.INFURA_API_KEY,
      walletconnectId: process.env.WALLETCONNECT_PROJECT_ID,
      // Dev flag: when true, the board lets the player choose pseudo-legal
      // moves (e.g. leaving their own king in check). Off by default; the
      // engine still accepts opponent illegal moves regardless.
      allowPseudoLegalMoves: process.env.ALLOW_PSEUDO_LEGAL === 'true',
      // CREATE2 puts the Lobby proxy at the same address on every chain.
      lobbyAddress: process.env.LOBBY_PROXY_ADDR,
      // getProvider() with no chainId defaults to mainnet where the Lobby isn't
      // deployed; spectator (no-wallet) reads target this chain instead.
      spectatorChainId: process.env.SPECTATOR_CHAIN_ID || '31337'
    }
  },
  hooks: {
    // https://github.com/WalletConnect/walletconnect-monorepo/issues/655
    // https://github.com/nuxt/framework/discussions/4393
    'vite:extendConfig'(clientConfig, { isClient }) {
      if (process.env.NODE_ENV == 'production') {
        clientConfig.resolve.alias['@walletconnect/ethereum-provider'] = path.resolve(
          __dirname,
          'node_modules/@walletconnect/ethereum-provider/dist/umd/index.min.js'
        )
      }
    }
  },
  vite: {
    plugins: [
      {
        name: 'composable-full-reload',
        handleHotUpdate({ file, server }) {
          if (file.includes('/composables/')) {
            server.ws.send({ type: 'full-reload' });
            return [];
          }
        }
      }
    ],
    build: {
      sourcemap: true,
    },
    // Workaround for Nuxt 3.20+ regression with `ssr: false`: Vite's pre-transform
    // import analysis fires before the dead-branch `if (false) import('#app-manifest')`
    // gets tree-shaken, so we explicitly exclude these virtual ids from pre-bundling.
    // See nuxt/nuxt#33606 — the fix in PR #34565 landed in 4.x only.
    optimizeDeps: {
      exclude: ['#app-manifest', '#build/route-rules.mjs'],
    },
  }
})
