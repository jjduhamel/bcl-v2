import path from 'path';
import { NodeGlobalsPolyfillPlugin } from '@esbuild-plugins/node-globals-polyfill';
import { NodeModulesPolyfillPlugin } from '@esbuild-plugins/node-modules-polyfill';
import rollupNodePolyfill from 'rollup-plugin-polyfill-node';

console.log('env', process.env.NODE_ENV);
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
          // Seems to be breaking rollupNodePolyfill
          //NodeModulesPolyfillPlugin()
        ],
      },
    },
    build: {
      sourcemap: true,
      // https://github.com/blocknative/web3-onboard/issues/762#issuecomment-997246672
      // https://stackoverflow.com/questions/71645151/cannnot-initialize-coinbasesdk-in-nuxt3-project
      plugins: [
        ...(process.env.NODE_ENV == 'development' ? [
          rollupNodePolyfill({
            include: [
              'node_modules/**/*.js',
              new RegExp('node_modules/.vite/.*js')
            ]
          })
        ] : [])
      ],
      rollupOptions: {
        plugins: [ rollupNodePolyfill() ]
      },
      commonjsOptions: {
        transformMixedEsModules: true
      }
    },
  }
})
