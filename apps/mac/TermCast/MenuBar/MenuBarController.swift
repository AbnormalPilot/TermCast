import AppKit

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var sessions: [Session] = []
    private var clientCount: Int = 0

    /// Called when the user selects "Pair another device…" from the menu.
    var onPairRequested: (() -> Void)?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌨️"
        statusItem.button?.action = #selector(statusBarButtonClicked)
        statusItem.button?.target = self
        setupMenu()
    }

    func update(sessions: [Session], clientCount: Int) {
        self.sessions = sessions
        self.clientCount = clientCount
        updateBadge()
        rebuildMenu()
    }

    private func updateBadge() {
        let badge = clientCount > 0 ? " \(clientCount)" : ""
        statusItem.button?.title = "⌨️\(badge)"
    }

    private func setupMenu() {
        menu = NSMenu()
        statusItem.menu = menu
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if sessions.isEmpty {
            let none = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for session in sessions {
                let item = NSMenuItem(
                    title: "\(session.termApp) — \(session.shell)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let clientItem = NSMenuItem(
            title: "\(clientCount) client\(clientCount == 1 ? "" : "s") connected",
            action: nil, keyEquivalent: ""
        )
        clientItem.isEnabled = false
        menu.addItem(clientItem)
        menu.addItem(.separator())
        let pairItem = NSMenuItem(
            title: "Pair another device…",
            action: #selector(pairDevice),
            keyEquivalent: ""
        )
        pairItem.target = self
        menu.addItem(pairItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(
            title: "Quit TermCast",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    @objc private func statusBarButtonClicked() {}
    @objc private func openPreferences() { NSApp.activate(ignoringOtherApps: true) }
    @objc private func pairDevice() { onPairRequested?() }
}
