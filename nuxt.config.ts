import path from 'path';
import { NodeGlobalsPolyfillPlugin } from '@esbuild-plugins/node-globals-polyfill';
import { NodeModulesPolyfillPlugin } from '@esbuild-plugins/node-modules-polyfill';

// https://v3.nuxtjs.org/api/configuration/nuxt.config
export default defineNuxtConfig({
  srcDir: 'client/',
  target: 'static',
  ssr: false,
  css: [ '@/assets/styles/tailwind.css' ],
  modules: [
    [ '@pinia/nuxt',
      { autoImports: [ 'defineStore' ] }
    ],
    '@nuxtjs/tailwindcss',
    '@vueuse/nuxt'
  ],
  runtimeConfig: {
    public: {
      amplitudeId: process.env.AMPLITUDE_API_KEY,
      bugsnagId: process.env.BUGSNAG_API_KEY,
      infuraId: process.env.INFURA_API_KEY,
      alchemyId: process.env.ALCHEMY_API_KEY,
      lobbyAddress: {
        local: process.env.LOCAL_LOBBY_ADDR,
        ethereum: process.env.HOMESTEAD_LOBBY_ADDR,
        goerli: process.env.GOERLI_LOBBY_ADDR,
        matic: process.env.MATIC_LOBBY_ADDR,
        mumbai: process.env.MUMBAI_LOBBY_ADDR
      }
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
    // Needed to make @walletconnect/web3-provider work
    // https://github.com/nuxt/framework/discussions/4393
    optimizeDeps: {
      esbuildOptions: {
        define: {
          global: 'globalThis',
        },
        plugins: [
          NodeGlobalsPolyfillPlugin({
            process: true,
            buffer: true
          }),
          NodeModulesPolyfillPlugin()
        ],
      },
    }
  }
})
