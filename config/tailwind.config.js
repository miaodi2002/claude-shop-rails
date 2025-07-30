module.exports = {
  content: [
    './public/*.html',
    './app/**/*.{js,jsx,ts,tsx,vue}',
    './app/**/*.html.erb',
    './app/**/*.erb',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        }
      }
    },
  },
  plugins: []
}