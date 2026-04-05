const { defineConfig } = require('cypress')
const path = require('path')

module.exports = defineConfig({
  e2e: {
    // Cypress will serve files from this folder when using cy.visit('/...')
    // Point it at the xterm assets directory so index.html is at the root
    fileServerFolder: path.resolve(__dirname, '../assets/xterm'),
    specPattern: 'cypress/e2e/**/*.cy.js',
    supportFile: 'cypress/support/commands.js',
    video: false,
    screenshotOnRunFailure: true,
    defaultCommandTimeout: 10000,
    experimentalModifyObstructiveThirdPartyCode: false,
  }
})
