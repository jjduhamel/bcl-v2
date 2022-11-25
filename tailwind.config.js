/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./client/assets/**/*.{vue,js,css}",
    "./client/components/**/*.{vue,js,ts}",
    "./client/layouts/**/*.vue",
    "./client/pages/**/*.vue",
    "./client/plugins/**/*.{js,ts}",
    "./nuxt.config.{js,ts}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
