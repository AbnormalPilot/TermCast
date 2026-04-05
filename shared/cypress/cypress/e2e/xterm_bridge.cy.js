// shared/cypress/cypress/e2e/xterm_bridge.cy.js

describe('xterm.js WebView bundle', () => {
  beforeEach(() => {
    cy.openTerminal()
    // Wait for xterm.js to initialise — onReady fires synchronously at script end
    cy.window().should(win => {
      expect(win.TermCastBridge._readyCalled).to.be.true
    })
  })

  it('page loads and onReady is called', () => {
    cy.window().then(win => {
      expect(win.TermCastBridge._readyCalled).to.be.true
    })
  })

  it('window.termWrite function exists', () => {
    cy.window().should(win => {
      expect(typeof win.termWrite).to.equal('function')
    })
  })

  it('window.termResize function exists', () => {
    cy.window().should(win => {
      expect(typeof win.termResize).to.equal('function')
    })
  })

  it('#terminal container exists in DOM', () => {
    cy.get('#terminal').should('exist')
  })

  it('.xterm container is rendered inside #terminal', () => {
    cy.get('#terminal .xterm').should('exist')
  })

  it('termWrite ASCII text does not throw', () => {
    // "Hello" in base64
    cy.window().then(win => {
      win.termWrite(win.btoa('Hello'))
    })
    // xterm container should still exist after write
    cy.get('#terminal .xterm').should('exist')
  })

  it('termWrite ESC sequence does not crash', () => {
    cy.window().then(win => {
      // ESC[H = cursor home
      win.termWrite(win.btoa('\x1b[H'))
    })
    cy.get('#terminal .xterm').should('exist')
  })

  it('termResize changes terminal without crashing', () => {
    cy.window().then(win => {
      win.termResize(120, 40)
    })
    cy.get('#terminal .xterm').should('exist')
  })

  it('termWrite large chunk does not crash', () => {
    cy.window().then(win => {
      const largeText = 'X'.repeat(4096)
      win.termWrite(win.btoa(largeText))
    })
    cy.get('#terminal .xterm').should('exist')
  })

  it('multiple sequential termWrites do not crash', () => {
    cy.window().then(win => {
      win.termWrite(win.btoa('Part1'))
      win.termWrite(win.btoa('Part2'))
      win.termWrite(win.btoa('Part3'))
    })
    cy.get('#terminal .xterm').should('exist')
  })

  it('bridge.onInput is called when user types in terminal', () => {
    // Focus the xterm textarea (xterm's input element) and type
    cy.get('textarea.xterm-helper-textarea').focus({ force: true }).type('a', { force: true })
    cy.window().should(win => {
      expect(win.TermCastBridge._inputCalls.length).to.be.greaterThan(0)
    })
  })
})
