import { NodeGlobalsPolyfillPlugin } from '@esbuild-plugins/node-globals-polyfill'
import { NodeModulesPolyfillPlugin } from '@esbuild-plugins/node-modules-polyfill'
import svgLoader from 'vite-svg-loader';

// https://v3.nuxtjs.org/api/configuration/nuxt.config
export default defineNuxtConfig({
  ssr: false,
  css: [ '@/assets/styles/tailwind.css' ],
  modules: [
    [ '@pinia/nuxt',
      { autoImports: [ 'defineStore' ] }
    ],
    '@nuxtjs/svg', /*'nuxt-icons', 'nuxt-svg-loader'*/
  ],
  build: {
    postcss: {
      postcssOptions: require('./postcss.config.js')
    }
  },
  runtimeConfig: {
    public: {
      contractAddress: {
        local: '0x8d4aa2f669939e6aef0e3a85e2591ba694f26774',
        homestead: null,
        goerli: null,
        rinkeby: null,
        matic: null,
        mumbai: null
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
