import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var registry: SessionRegistry!
    private var broadcaster: SessionBroadcaster!
    private var socketServer: AgentSocketServer!
    private var wsServer: WebSocketServer!
    private var jwtManager: JWTManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Load or generate JWT secret
        let secret: Data
        if let stored = try? KeychainStore.load(key: "jwt-secret") {
            secret = stored
        } else {
            let generated = JWTManager.generateSecret()
            try? KeychainStore.save(key: "jwt-secret", data: generated)
            secret = generated
        }
        jwtManager = JWTManager(secret: secret)

        // 2. Core components
        registry = SessionRegistry()
        broadcaster = SessionBroadcaster()
        menuBar = MenuBarController()

        // 3. Wire registry → broadcaster → menu bar
        let reg = registry!
        let bc = broadcaster!
        Task {
            await reg.setOnSessionAdded { [weak self] session in
                Task { @MainActor [weak self] in
                    await bc.broadcastSessionOpened(session)
                    await self?.refreshMenuBar()
                }
            }
            await reg.setOnSessionRemoved { [weak self] id in
                Task { @MainActor [weak self] in
                    await bc.broadcastSessionClosed(id)
                    await self?.refreshMenuBar()
                }
            }
        }

        // 4. Start Unix socket server
        socketServer = AgentSocketServer(
            socketPath: NSHomeDirectory() + "/.termcast/agent.sock"
        ) { [weak self] regMsg in
            await self?.registry.register(regMsg)
        }

        // 5. Start WebSocket server
        wsServer = WebSocketServer(
            port: 7681,
            jwtManager: jwtManager,
            registry: registry,
            broadcaster: broadcaster
        )

        let ss = socketServer!
        let ws = wsServer!
        Task {
            do {
                let group = await ws.group
                try await ss.start(group: group)
                try await ws.start()
            } catch {
                fputs("TermCast: failed to start servers: \(error)\n", stderr)
            }
        }

        // 6. First-launch setup
        if !ShellHookInstaller.isInstalled() {
            performFirstLaunchSetup()
        }

        // 7. Recover any live sessions from /tmp/termcast/
        recoverSessions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let ss = socketServer
        let ws = wsServer
        Task {
            try? await ss?.stop()
            try? await ws?.stop()
        }
    }

    // MARK: - Private

    private func performFirstLaunchSetup() {
        Task { @MainActor in
            try? ShellHookInstaller.install()
            guard TailscaleSetup.isTailscaleInstalled() else {
                self.showAlert("Tailscale Required",
                               "Install Tailscale from tailscale.com, then relaunch TermCast.")
                return
            }
            try? TailscaleSetup.configureServe()
            guard let hostname = try? TailscaleSetup.hostname() else { return }
            guard let secret = try? KeychainStore.load(key: "jwt-secret"),
                  let qr = TailscaleSetup.qrCode(hostname: hostname, secret: secret) else { return }
            self.showQRWindow(qr: qr, hostname: hostname)
        }
    }

    private func recoverSessions() {
        let dir = "/tmp/termcast"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for file in files where file.hasSuffix(".out") {
            guard let pidStr = file.components(separatedBy: ".").first,
                  let pid = Int(pidStr) else { continue }
            if kill(Int32(pid), 0) == 0 {
                let reg = ShellRegistration(
                    pid: pid, tty: "/dev/tty",
                    shell: "zsh", term: "unknown",
                    outPipe: "\(dir)/\(file)"
                )
                Task { [weak self] in await self?.registry.register(reg) }
            } else {
                try? FileManager.default.removeItem(atPath: "\(dir)/\(file)")
            }
        }
    }

    @MainActor
    private func refreshMenuBar() async {
        let sessions = await registry.allSessions()
        let count = await broadcaster.clientCount
        menuBar.update(sessions: sessions, clientCount: count)
    }

    @MainActor
    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @MainActor
    private func showQRWindow(qr: NSImage, hostname: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Pair TermCast"
        window.center()
        let view = NSView(frame: window.contentView!.bounds)
        let imageView = NSImageView(frame: NSRect(x: 60, y: 60, width: 200, height: 200))
        imageView.image = qr
        let label = NSTextField(frame: NSRect(x: 20, y: 20, width: 280, height: 30))
        label.stringValue = "Scan with TermCast mobile app"
        label.isEditable = false
        label.isBordered = false
        label.alignment = .center
        view.addSubview(imageView)
        view.addSubview(label)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
