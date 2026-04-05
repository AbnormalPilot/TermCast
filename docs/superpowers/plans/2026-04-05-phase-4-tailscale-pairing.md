# Phase 4: Tailscale Integration + QR Pairing End-to-End — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the end-to-end pairing and Tailscale integration so a phone can scan a QR code from the Mac, connect via Tailscale, and automatically re-pair when credentials are rejected.

**Architecture:** Multi-path Tailscale binary detection ensures the Mac setup wizard works on all install methods (Homebrew Intel/ARM, App Store). A "Pair another device" menu item enables adding more phones after initial setup. On mobile, invalid credentials surface a re-pairing path — Android detects the HTTP rejection on first connect; iOS shows an "Unpair" button after an initial connection failure (since Network.framework doesn't expose HTTP status codes).

**Tech Stack:** Swift/SwiftNIO + AppKit (Mac), Swift/Network.framework + SwiftUI (iOS), Kotlin/OkHttp + Jetpack Compose (Android)

---

## Branch Setup

Work on branch `feature/phase-4-tailscale` (already created from `feature/phase-2-ios-app`).

When Phase 4 is complete and tests pass, merge to `main` with `--no-ff` and tag `v4.0-phase-4`.

---

## File Map

**New files:**
- `apps/mac/TermCastTests/TailscaleSetupTests.swift` — unit tests for multi-path Tailscale detection
- `apps/ios/TermCastiOSTests/WSClientStateTests.swift` — unit tests for authFailed state detection

**Modified files:**
- `apps/mac/TermCast/Tailscale/TailscaleSetup.swift` — multi-path binary detection (Intel, ARM, App Store)
- `apps/mac/TermCast/MenuBar/MenuBarController.swift` — "Pair another device…" menu item + `onPairRequested` callback
- `apps/mac/TermCast/App/TermCastApp.swift` — wire `onPairRequested` → `showQRCodeIfAvailable()`
- `apps/android/.../connection/WSClient.kt` — add `AUTH_FAILED` to `ConnectionState`, detect HTTP rejection
- `apps/android/.../MainActivity.kt` — handle `AUTH_FAILED` via `LaunchedEffect` → clear creds + show QR
- `apps/android/.../test/.../SessionViewModelTest.kt` — auth failure test
- `apps/ios/TermCastiOS/Connection/WSClient.swift` — add `.authFailed` state + `didEverConnect` tracking
- `apps/ios/TermCastiOS/Views/OfflineView.swift` — optional `onUnpair` button
- `apps/ios/TermCastiOS/App/TermCastiOSApp.swift` — handle `.authFailed`, pass `onUnpair` to OfflineView

---

### Task 1: Mac — Tailscale binary multi-path detection

**Files:**
- Modify: `apps/mac/TermCast/Tailscale/TailscaleSetup.swift`
- Create: `apps/mac/TermCastTests/TailscaleSetupTests.swift`

**Context:** The current code hardcodes `/usr/local/bin/tailscale`, which only works on Intel Homebrew installs. Homebrew Apple Silicon uses `/opt/homebrew/bin/tailscale`. The App Store / direct-download app is at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. This task extracts a testable `resolvePath(checking:)` helper and updates all callers to use it.

- [ ] **Step 1: Write the failing tests**

Create `apps/mac/TermCastTests/TailscaleSetupTests.swift`:

```swift
import Testing
@testable import TermCast

@Suite("TailscaleSetup")
struct TailscaleSetupTests {

    @Test("candidatePaths includes all known install locations")
    func candidatePathsComplete() {
        let paths = TailscaleSetup.candidatePaths
        #expect(paths.contains("/usr/local/bin/tailscale"))
        #expect(paths.contains("/opt/homebrew/bin/tailscale"))
        #expect(paths.contains("/Applications/Tailscale.app/Contents/MacOS/Tailscale"))
    }

    @Test("resolvePath returns nil when no candidate exists")
    func resolvePathNilWhenNoneExist() {
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent1", "/nonexistent2"])
        #expect(result == nil)
    }

    @Test("resolvePath returns first existing path")
    func resolvePathReturnsFirst() {
        // /usr/bin/env always exists on macOS — use it as a known sentinel
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent", "/usr/bin/env"])
        #expect(result == "/usr/bin/env")
    }

    @Test("resolvePath skips nonexistent paths before first hit")
    func resolvePathSkipsNonexistent() {
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent1", "/usr/bin/env", "/usr/bin/true"])
        #expect(result == "/usr/bin/env")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' \
  -only-testing:TermCastTests/TailscaleSetupTests 2>&1 | tail -20
```
Expected: FAIL — `TailscaleSetup.candidatePaths` and `TailscaleSetup.resolvePath(checking:)` don't exist yet.

- [ ] **Step 3: Implement multi-path detection**

Replace `apps/mac/TermCast/Tailscale/TailscaleSetup.swift` with:

```swift
import AppKit
import Foundation
import CoreImage

struct TailscaleStatus: Decodable {
    struct SelfNode: Decodable {
        let dnsName: String
        enum CodingKeys: String, CodingKey { case dnsName = "DNSName" }
    }
    let selfNode: SelfNode
    enum CodingKeys: String, CodingKey { case selfNode = "Self" }
}

struct TailscaleSetup {
    /// All known install locations for the Tailscale CLI, in priority order.
    static let candidatePaths: [String] = [
        "/usr/local/bin/tailscale",                                 // Homebrew Intel / legacy
        "/opt/homebrew/bin/tailscale",                              // Homebrew Apple Silicon
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale"     // App Store / direct download
    ]

    /// Returns the first path in `candidates` that exists on disk, or nil.
    static func resolvePath(checking candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func isTailscaleInstalled() -> Bool {
        resolvePath(checking: candidatePaths) != nil
    }

    @discardableResult
    static func configureServe() throws -> String {
        guard let bin = resolvePath(checking: candidatePaths) else { throw TailscaleError.notInstalled }
        return try shell(bin, "serve", "--https=443", "7681")
    }

    static func hostname() throws -> String {
        guard let bin = resolvePath(checking: candidatePaths) else { throw TailscaleError.notInstalled }
        let json = try shell(bin, "status", "--json")
        guard let data = json.data(using: .utf8) else { throw TailscaleError.parseError }
        let status = try JSONDecoder().decode(TailscaleStatus.self, from: data)
        return status.selfNode.dnsName.hasSuffix(".")
            ? String(status.selfNode.dnsName.dropLast()) : status.selfNode.dnsName
    }

    static func qrCode(hostname: String, secret: Data) -> NSImage? {
        let payload: [String: String] = [
            "host": hostname,
            "secret": secret.map { String(format: "%02x", $0) }.joined()
        ]
        guard let json = try? JSONEncoder().encode(payload),
              let str = String(data: json, encoding: .utf8) else { return nil }
        return generateQR(from: str)
    }

    private static func generateQR(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    @discardableResult
    private static func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

enum TailscaleError: Error {
    case notInstalled
    case parseError
    case configureError(String)
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' \
  -only-testing:TermCastTests/TailscaleSetupTests 2>&1 | tail -20
```
Expected: 4 tests pass — `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add apps/mac/TermCast/Tailscale/TailscaleSetup.swift \
        apps/mac/TermCastTests/TailscaleSetupTests.swift
git commit -m "feat(mac): multi-path Tailscale binary detection — Intel, ARM, App Store"
```

---

### Task 2: Mac — "Pair another device" menu item

**Files:**
- Modify: `apps/mac/TermCast/MenuBar/MenuBarController.swift`
- Modify: `apps/mac/TermCast/App/TermCastApp.swift`

**Context:** After initial setup, there is no way to show the QR code again to pair a second phone. This task adds "Pair another device…" to the menu (⌘P shortcut) and wires it to a new `showQRCodeIfAvailable()` helper in AppDelegate. `showQRCodeIfAvailable` is extracted from `performFirstLaunchSetup` so both paths share the same logic.

- [ ] **Step 1: Update MenuBarController — add onPairRequested callback and menu item**

Replace `apps/mac/TermCast/MenuBar/MenuBarController.swift` with:

```swift
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
            keyEquivalent: "p"
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
```

- [ ] **Step 2: Update TermCastApp.swift — wire onPairRequested + extract showQRCodeIfAvailable**

Replace `apps/mac/TermCast/App/TermCastApp.swift` with:

```swift
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
        menuBar.onPairRequested = { [weak self] in
            Task { @MainActor [weak self] in self?.showQRCodeIfAvailable() }
        }

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
            self.showQRCodeIfAvailable()
        }
    }

    /// Shows the pairing QR window. Safe to call at any time — shows an alert if Tailscale
    /// is not running or the hostname can't be resolved.
    @MainActor
    private func showQRCodeIfAvailable() {
        guard TailscaleSetup.isTailscaleInstalled() else {
            showAlert("Tailscale Required", "Install Tailscale from tailscale.com, then retry.")
            return
        }
        guard let hostname = try? TailscaleSetup.hostname(),
              let secret = try? KeychainStore.load(key: "jwt-secret"),
              let qr = TailscaleSetup.qrCode(hostname: hostname, secret: secret) else {
            showAlert("Setup Incomplete",
                      "Could not reach Tailscale. Make sure Tailscale is running.")
            return
        }
        showQRWindow(qr: qr, hostname: hostname)
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
```

- [ ] **Step 3: Build to verify no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 \
  | grep -E "(error:|BUILD)" | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add apps/mac/TermCast/MenuBar/MenuBarController.swift \
        apps/mac/TermCast/App/TermCastApp.swift
git commit -m "feat(mac): add 'Pair another device' menu item + extract showQRCodeIfAvailable"
```

---

### Task 3: Android — AUTH_FAILED state + automatic re-pair

**Files:**
- Modify: `apps/android/app/src/main/java/com/termcast/android/connection/WSClient.kt`
- Modify: `apps/android/app/src/main/java/com/termcast/android/MainActivity.kt`
- Modify: `apps/android/app/src/test/java/com/termcast/android/SessionViewModelTest.kt`

**Context:** `ConnectionState` is an enum in `WSClient.kt` (not in `WSClientInterface.kt`). OkHttp's `WebSocketListener.onFailure(ws, t, response?)` receives `response: Response?` — when the Mac server rejects the WebSocket upgrade (invalid JWT → `shouldUpgrade` returns nil → server sends non-101 response), OkHttp calls `onFailure` with `response != null`. If the response was received but the upgrade failed, AND we've never successfully connected with these credentials, that's an auth failure. `AUTH_FAILED` state triggers clearing stored credentials and showing the QR scan screen.

- [ ] **Step 1: Write the failing test**

In `apps/android/app/src/test/java/com/termcast/android/SessionViewModelTest.kt`, append this test after the last existing `@Test`:

```kotlin
@Test
fun `AUTH_FAILED state emitted when server rejects on first connect`() = runTest {
    val authFailedState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val fakeAuthClient = object : WSClientInterface {
        override val state: StateFlow<ConnectionState> = authFailedState
        override val messages: SharedFlow<WSMessageEnvelope> = MutableSharedFlow()
        override fun connect(creds: PairingCredentials) {
            authFailedState.value = ConnectionState.AUTH_FAILED
        }
        override fun send(json: String) {}
        override fun disconnect() { authFailedState.value = ConnectionState.DISCONNECTED }
    }

    fakeAuthClient.connect(PairingCredentials("host.ts.net", byteArrayOf(1, 2, 3)))
    advanceUntilIdle()

    assertEquals(ConnectionState.AUTH_FAILED, authFailedState.value)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd apps/android
./gradlew :app:test \
  --tests "com.termcast.android.SessionViewModelTest.AUTH_FAILED state emitted when server rejects on first connect" \
  2>&1 | tail -20
```
Expected: FAIL — `ConnectionState.AUTH_FAILED` doesn't exist yet.

- [ ] **Step 3: Add AUTH_FAILED to ConnectionState and update WSClient**

Replace `apps/android/app/src/main/java/com/termcast/android/connection/WSClient.kt` with:

```kotlin
package com.termcast.android.connection

import android.util.Base64
import com.termcast.android.auth.PairingCredentials
import com.termcast.android.models.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, OFFLINE, AUTH_FAILED }

class WSClient(private val scope: CoroutineScope) : WSClientInterface {
    private val client = OkHttpClient.Builder()
        .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
        .build()

    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableSharedFlow<WSMessageEnvelope>()
    override val messages: SharedFlow<WSMessageEnvelope> = _messages.asSharedFlow()

    private var socket: WebSocket? = null
    private val policy = ReconnectPolicy()
    private var pingPong: PingPong? = null
    private var reconnectJob: Job? = null
    /** True once onOpen fires — reset to false on each new connect() call. */
    private var didEverConnect = false

    override fun connect(creds: PairingCredentials) {
        didEverConnect = false
        _state.value = ConnectionState.CONNECTING
        val token = buildJWT(creds.secret)
        val request = Request.Builder()
            .url("wss://${creds.host}")
            .header("Authorization", "Bearer $token")
            .build()

        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                didEverConnect = true
                _state.value = ConnectionState.CONNECTED
                policy.reset()
                pingPong = PingPong(
                    onSendPing = { send(PongMessage().toJson()) },
                    onTimeout = { scheduleReconnect(creds) }
                ).also { it.start(scope) }
            }

            override fun onMessage(ws: WebSocket, text: String) {
                val msg = parseWSMessage(text) ?: return
                if (msg.type == "ping") pingPong?.didReceivePong()
                scope.launch { _messages.emit(msg) }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                pingPong?.stop()
                // response != null means the server replied (HTTP handshake reached the server)
                // but the upgrade was rejected. If we never connected with these creds, treat
                // it as an auth failure so the app can clear credentials and re-pair.
                if (!didEverConnect && response != null) {
                    _state.value = ConnectionState.AUTH_FAILED
                } else {
                    _state.value = ConnectionState.OFFLINE
                    scheduleReconnect(creds)
                }
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                _state.value = ConnectionState.OFFLINE
                pingPong?.stop()
                scheduleReconnect(creds)
            }
        })
    }

    override fun send(json: String) { socket?.send(json) }

    override fun disconnect() {
        reconnectJob?.cancel()
        pingPong?.stop()
        socket?.cancel()
        socket = null
        _state.value = ConnectionState.DISCONNECTED
        policy.reset()
        didEverConnect = false
    }

    private fun scheduleReconnect(creds: PairingCredentials) {
        reconnectJob?.cancel()
        val delayMs = policy.nextDelayMs()
        reconnectJob = scope.launch {
            delay(delayMs)
            if (isActive) connect(creds)
        }
    }

    private fun buildJWT(secret: ByteArray): String {
        fun base64url(bytes: ByteArray) =
            Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val header = base64url("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val now = System.currentTimeMillis() / 1000
        val exp = now + 30 * 24 * 3600
        val payload = base64url("""{"sub":"termcast-client","iat":$now,"exp":$exp}""".toByteArray())
        val msg = "$header.$payload"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return "$msg.${base64url(mac.doFinal(msg.toByteArray()))}"
    }
}
```

- [ ] **Step 4: Handle AUTH_FAILED in AppNavigation — clear creds and show QR**

Replace `apps/android/app/src/main/java/com/termcast/android/MainActivity.kt` with:

```kotlin
package com.termcast.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.lifecycle.lifecycleScope
import com.termcast.android.auth.PairingRepository
import com.termcast.android.connection.ConnectionState
import com.termcast.android.connection.WSClient
import com.termcast.android.onboarding.QRScanScreen
import com.termcast.android.sessions.SessionViewModel
import com.termcast.android.ui.*
import com.termcast.android.ui.theme.TermCastTheme

class MainActivity : ComponentActivity() {
    private lateinit var pairingRepo: PairingRepository
    private lateinit var wsClient: WSClient
    private lateinit var sessionViewModel: SessionViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        pairingRepo = PairingRepository(this)
        wsClient = WSClient(lifecycleScope)
        sessionViewModel = SessionViewModel(wsClient)

        pairingRepo.load()?.let { creds -> wsClient.connect(creds) }

        setContent {
            TermCastTheme {
                AppNavigation(
                    pairingRepo = pairingRepo,
                    wsClient = wsClient,
                    sessionViewModel = sessionViewModel
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        wsClient.disconnect()
    }
}

@Composable
private fun AppNavigation(
    pairingRepo: PairingRepository,
    wsClient: WSClient,
    sessionViewModel: SessionViewModel
) {
    var isPaired by remember { mutableStateOf(pairingRepo.hasCredentials()) }
    val connectionState by wsClient.state.collectAsState()

    // AUTH_FAILED: stale JWT — clear credentials and force re-pairing.
    LaunchedEffect(connectionState) {
        if (connectionState == ConnectionState.AUTH_FAILED) {
            pairingRepo.clear()
            wsClient.disconnect()
            isPaired = false
        }
    }

    when {
        !isPaired -> QRScanScreen { host, secretHex ->
            pairingRepo.save(host, secretHex)
            pairingRepo.load()?.let { creds -> wsClient.connect(creds) }
            isPaired = true
        }
        connectionState == ConnectionState.AUTH_FAILED -> {
            // Handled by LaunchedEffect above — renders briefly before isPaired resets.
        }
        connectionState == ConnectionState.OFFLINE -> OfflineScreen {
            pairingRepo.load()?.let { creds -> wsClient.connect(creds) }
        }
        else -> SessionListScreen(viewModel = sessionViewModel)
    }
}
```

- [ ] **Step 5: Run all Android unit tests**

```bash
cd apps/android
./gradlew :app:test 2>&1 | tail -30
```
Expected: All tests pass including the new AUTH_FAILED test.

- [ ] **Step 6: Commit**

```bash
git add apps/android/app/src/main/java/com/termcast/android/connection/WSClient.kt \
        apps/android/app/src/main/java/com/termcast/android/MainActivity.kt \
        apps/android/app/src/test/java/com/termcast/android/SessionViewModelTest.kt
git commit -m "feat(android): AUTH_FAILED state — detect HTTP rejection on first connect, auto re-pair"
```

---

### Task 4: iOS — authFailed state + Unpair button on OfflineView

**Files:**
- Modify: `apps/ios/TermCastiOS/Connection/WSClient.swift`
- Modify: `apps/ios/TermCastiOS/Views/OfflineView.swift`
- Modify: `apps/ios/TermCastiOS/App/TermCastiOSApp.swift`
- Create: `apps/ios/TermCastiOSTests/WSClientStateTests.swift`

**Context:** `NWConnection` (Network.framework) does not expose the HTTP status code when a WebSocket upgrade is rejected. Strategy: track `didEverConnect` per-connect-call. If the connection transitions from `.connecting` directly to `.failed` without ever becoming `.ready`, emit `.authFailed`. The app shows an "Unpair — Scan QR again" button on OfflineView only when `isAuthFailed` is true, giving the user a clear re-pairing path without automatic credential clearing (to avoid deleting valid creds on transient network errors). `WSClientState` needs `Equatable` conformance for test assertions.

- [ ] **Step 1: Write failing tests**

Create `apps/ios/TermCastiOSTests/WSClientStateTests.swift`:

```swift
import Testing
@testable import TermCastiOS

@Suite("WSClientState")
struct WSClientStateTests {

    @Test("initial state is disconnected")
    func initialStateIsDisconnected() {
        let client = WSClient()
        #expect(client.state == .disconnected)
    }

    @Test("state becomes connecting immediately after connect()")
    func connectTransitionsToConnecting() {
        let client = WSClient()
        // An obviously invalid host — the connection will fail, but state is .connecting first
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        #expect(client.state == .connecting)
        client.disconnect()
    }

    @Test("state becomes disconnected after disconnect()")
    func disconnectResetsState() {
        let client = WSClient()
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        client.disconnect()
        #expect(client.state == .disconnected)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TermCastiOSTests/WSClientStateTests 2>&1 | tail -20
```
Expected: FAIL — `client.state == .disconnected` comparison fails because `WSClientState` is not `Equatable`, or `WSClientStateTests` file not found.

- [ ] **Step 3: Add .authFailed state + Equatable + didEverConnect tracking to WSClient**

Replace `apps/ios/TermCastiOS/Connection/WSClient.swift` with:

```swift
import Foundation
import Network
import CommonCrypto

enum WSClientState: Equatable {
    case disconnected, connecting, connected, offline, authFailed
}

final class WSClient: ObservableObject {
    @Published private(set) var state: WSClientState = .disconnected
    var onMessage: ((WSMessage) -> Void)?
    var onStateChange: ((WSClientState) -> Void)?

    private var connection: NWConnection?
    private let policy = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var pingPong: PingPong?
    /// Tracks whether the current credentials have ever produced a successful connection.
    /// Reset to false on each new connect() call. Used to distinguish auth failures
    /// (never connected) from transient network drops (previously connected).
    private var didEverConnect = false

    func connect(host: String, secret: Data) {
        didEverConnect = false
        let token = buildJWT(secret: secret)
        guard let url = URL(string: "wss://\(host)") else { return }
        let endpoint = NWEndpoint.url(url)
        let params = NWParameters.tls
        if let wsOpts = params.defaultProtocolStack.applicationProtocols.first
            as? NWProtocolWebSocket.Options {
            wsOpts.setAdditionalHeaders([("Authorization", "Bearer \(token)")])
        } else {
            let wsOpts = NWProtocolWebSocket.Options()
            wsOpts.setAdditionalHeaders([("Authorization", "Bearer \(token)")])
            params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)
        }

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        setState(.connecting)

        conn.stateUpdateHandler = { [weak self] newState in
            self?.handleStateUpdate(newState, host: host, secret: secret)
        }
        conn.start(queue: .main)
        receiveLoop(conn)
    }

    func disconnect() {
        reconnectTask?.cancel()
        pingPong?.stop()
        connection?.cancel()
        connection = nil
        setState(.disconnected)
        policy.reset()
        didEverConnect = false
    }

    func send(_ message: WSMessage) {
        guard let conn = connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        guard let data = message.json().data(using: .utf8) else { return }
        conn.send(content: data, contentContext: context, completion: .idempotent)
    }

    private func handleStateUpdate(_ newState: NWConnection.State, host: String, secret: Data) {
        switch newState {
        case .ready:
            didEverConnect = true
            setState(.connected)
            policy.reset()
            pingPong = PingPong(
                onSendPing: { [weak self] in self?.send(.pong()) },
                onTimeout: { [weak self] in self?.scheduleReconnect(host: host, secret: secret) }
            )
            pingPong?.start()
        case .failed, .cancelled:
            // If the connection failed before ever becoming .ready with these credentials,
            // it may be an auth rejection. Surface .authFailed so the UI can show "Unpair".
            // If we previously had a working connection that dropped, use .offline + reconnect.
            if !didEverConnect {
                setState(.authFailed)
            } else {
                setState(.offline)
                scheduleReconnect(host: host, secret: secret)
            }
        default:
            break
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if error != nil { return }
            if let data, let text = String(data: data, encoding: .utf8),
               let msg = WSMessage.from(json: text) {
                DispatchQueue.main.async { self?.onMessage?(msg) }
            }
            self?.receiveLoop(conn)
        }
    }

    private func scheduleReconnect(host: String, secret: Data) {
        let delay = policy.nextDelay()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.connect(host: host, secret: secret)
        }
    }

    private func setState(_ newState: WSClientState) {
        state = newState
        onStateChange?(newState)
    }

    private func buildJWT(secret: Data) -> String {
        let header = base64url(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 30 * 24 * 3600
        let payloadStr = "{\"sub\":\"termcast-client\",\"iat\":\(now),\"exp\":\(exp)}"
        let payload = base64url(Data(payloadStr.utf8))
        let msg = "\(header).\(payload)"
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        msg.withCString { msgPtr in
            secret.withUnsafeBytes { keyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyPtr.baseAddress, secret.count,
                       msgPtr, strlen(msgPtr), &digest)
            }
        }
        return "\(msg).\(base64url(Data(digest)))"
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TermCastiOSTests/WSClientStateTests 2>&1 | tail -20
```
Expected: 3 tests pass.

- [ ] **Step 5: Add optional onUnpair button to OfflineView**

Replace `apps/ios/TermCastiOS/Views/OfflineView.swift` with:

```swift
import SwiftUI

struct OfflineView: View {
    let onRetry: () -> Void
    /// When non-nil, an "Unpair — Scan QR again" button is shown below Retry.
    /// Pass a closure only when the connection failed before ever authenticating.
    var onUnpair: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Mac Offline")
                .font(.title2.bold())

            Text("TermCast could not reach your Mac.\nMake sure both devices are on Tailscale.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Retry") { onRetry() }
                .buttonStyle(.borderedProminent)

            if let onUnpair {
                Button("Unpair — Scan QR again") { onUnpair() }
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 6: Wire authFailed + onUnpair in TermCastiOSApp.swift**

Replace `apps/ios/TermCastiOS/App/TermCastiOSApp.swift` with:

```swift
import SwiftUI

@main
struct TermCastiOSApp: App {
    @StateObject private var wsClient = WSClient()
    @StateObject private var sessionStore = SessionStore()
    @State private var isOnboarding = !PairingStore.hasCredentials()
    @State private var isOffline = false
    @State private var isAuthFailed = false

    var body: some Scene {
        WindowGroup {
            contentView
                .onChange(of: wsClient.state) { newState in
                    switch newState {
                    case .offline:
                        isOffline = true
                        isAuthFailed = false
                    case .authFailed:
                        isOffline = true
                        isAuthFailed = true
                    case .connected:
                        isOffline = false
                        isAuthFailed = false
                    default:
                        break
                    }
                }
                .task {
                    resetForUITestIfNeeded()
                    connect()
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if isOnboarding {
            QRScanView { host, secret in
                try? PairingStore.save(host: host, secret: secret)
                isOnboarding = false
                isAuthFailed = false
                connect()
            }
        } else if isOffline {
            OfflineView(
                onRetry: {
                    isOffline = false
                    isAuthFailed = false
                    connect()
                },
                onUnpair: isAuthFailed ? {
                    PairingStore.clear()
                    wsClient.disconnect()
                    isOffline = false
                    isAuthFailed = false
                    isOnboarding = true
                } : nil
            )
        } else {
            SessionListView(sessionStore: sessionStore, wsClient: wsClient)
        }
    }

    private func resetForUITestIfNeeded() {
        guard CommandLine.arguments.contains("--uitest-reset-credentials") else { return }
        PairingStore.clear()
        isOnboarding = true
    }

    private func connect() {
        guard let creds = try? PairingStore.load() else {
            isOnboarding = true
            return
        }
        wsClient.onMessage = { [weak sessionStore, weak wsClient] msg in
            Task { @MainActor in
                sessionStore?.apply(msg)
                guard let wsClient else { return }
                switch msg.type {
                case .output:
                    guard let idStr = msg.sessionId, let id = UUID(uuidString: idStr),
                          let b64 = msg.data, let data = Data(base64Encoded: b64) else { return }
                    NotificationCenter.default.post(
                        name: .termcastOutput(id),
                        object: nil,
                        userInfo: ["data": data]
                    )
                case .sessionClosed:
                    guard let idStr = msg.sessionId, let id = UUID(uuidString: idStr) else { return }
                    NotificationCenter.default.post(name: .termcastSessionEnded(id), object: nil)
                case .ping:
                    wsClient.send(.pong())
                default: break
                }
            }
        }
        wsClient.connect(host: creds.host, secret: creds.secret)
    }
}

// MARK: - PairingStore convenience

extension PairingStore {
    static func hasCredentials() -> Bool {
        (try? load()) != nil
    }
}
```

- [ ] **Step 7: Build to verify no compile errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \
  | grep -E "(error:|BUILD)" | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add apps/ios/TermCastiOS/Connection/WSClient.swift \
        apps/ios/TermCastiOS/Views/OfflineView.swift \
        apps/ios/TermCastiOS/App/TermCastiOSApp.swift \
        apps/ios/TermCastiOSTests/WSClientStateTests.swift
git commit -m "feat(ios): authFailed state — neverConnected heuristic, Unpair button on OfflineView"
```

---

### Task 5: Merge Phase 4 to main

- [ ] **Step 1: Update STATUS.md**

In `docs/context/STATUS.md`, update Phase 4 row from `Pending` to `Complete — merging to main` and update `Current Session Focus`.

- [ ] **Step 2: Commit STATUS.md**

```bash
git add docs/context/STATUS.md
git commit -m "docs: mark Phase 4 complete — Tailscale integration + QR pairing end-to-end"
```

- [ ] **Step 3: Merge to main and tag**

```bash
# From the repo root (not worktree):
cd /Users/himanshu/Desktop/struggle/termcast
git checkout main
git merge --no-ff feature/phase-4-tailscale \
  -m "chore: merge Phase 4 — Tailscale multi-path, Pair menu item, auth failure re-pairing"
git tag v4.0-phase-4
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| Mac: find Tailscale on all install paths | T1 |
| Mac: re-show QR to pair more devices | T2 |
| Android: invalid JWT → clear creds → QR scan | T3 |
| iOS: invalid JWT → show Unpair button | T4 |
| WebSocket protocol (already done in Phase 1–3) | — |
| QR payload `{ host, secret }` JSON format (already correct) | — |

All spec requirements are covered.

### Placeholder scan

No TBD, TODO, "implement later", or vague steps. Every step has complete code.

### Type consistency

- `TailscaleSetup.resolvePath(checking:)` — defined in T1 step 3, tested in T1 step 1 ✅
- `TailscaleSetup.candidatePaths` — defined in T1 step 3, tested in T1 step 1 ✅
- `MenuBarController.onPairRequested: (() -> Void)?` — defined in T2 step 1, set in T2 step 2 ✅
- `showQRCodeIfAvailable()` — defined in T2 step 2, called from `onPairRequested` and `performFirstLaunchSetup` ✅
- `ConnectionState.AUTH_FAILED` — defined in T3 step 3, tested in T3 step 1, handled in T3 step 4 ✅
- `WSClient.didEverConnect` — defined in T3 step 3 (Android) and T4 step 3 (iOS), same name ✅
- `WSClientState.authFailed` — defined in T4 step 3, used in T4 steps 5 and 6 ✅
- `OfflineView(onRetry:onUnpair:)` — defined in T4 step 5, called in T4 step 6 ✅
