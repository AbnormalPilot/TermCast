// shared/cypress/cypress/support/commands.js

/**
 * Open the xterm.js HTML bundle with a fake TermCastBridge injected.
 * The bridge records all calls so tests can assert on them.
 *
 * cypress.config.js sets fileServerFolder to shared/assets/xterm so
 * cy.visit('/index.html') resolves to that file via Cypress's built-in
 * static file server — no `file://` protocol needed.
 */
Cypress.Commands.add('openTerminal', () => {
  cy.visit('/index.html', {
    onBeforeLoad(win) {
      win.TermCastBridge = {
        _inputCalls: [],
        _resizeCalls: [],
        _readyCalled: false,

        onInput(base64) { this._inputCalls.push(base64) },
        onResize(cols, rows) { this._resizeCalls.push({ cols, rows }) },
        onReady() { this._readyCalled = true },
      }
    }
  })
})
