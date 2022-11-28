import { NodeGlobalsPolyfillPlugin } from '@esbuild-plugins/node-globals-polyfill'
import { NodeModulesPolyfillPlugin } from '@esbuild-plugins/node-modules-polyfill'
import svgLoader from 'vite-svg-loader';

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
    /*'@nuxtjs/svg', 'nuxt-icons', 'nuxt-svg-loader'*/
  ],
  runtimeConfig: {
    public: {
      infuraId: process.env.INFURA_ID,
      lobbyAddress: {
        local: process.env.LOCAL_LOBBY_ADDR,
        ethereum: process.env.HOMESTEAD_LOBBY_ADDR,
        goerli: process.env.GOERLI_LOBBY_ADDR,
        matic: process.env.MATIC_LOBBY_ADDR,
        mumbai: process.env.MUMBAI_LOBBY_ADDR
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
            buffer: true,
          }),
          NodeModulesPolyfillPlugin()
        ],
      },
    }
  }
})
