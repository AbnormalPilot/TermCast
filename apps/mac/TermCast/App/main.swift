import AppKit

// Minimal entry point — full implementation wired in P1-T15.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
