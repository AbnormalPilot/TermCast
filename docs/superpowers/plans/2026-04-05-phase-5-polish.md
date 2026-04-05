# Phase 5: Polish + Error States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the three remaining functional gaps: Mac port conflict detection, iOS ring buffer replay on session open, and manual smoke test documentation.

**Architecture:** Port conflict handling lives entirely in `WebSocketServer.swift` (try 7681→7685, return bound port) with persistence in `TermCastApp.swift` via `UserDefaults`. Ring buffer replay on iOS is a one-line `onAppear` in `SessionTabView` that sends an `attach` message. Smoke tests are a Markdown checklist in `docs/context/`.

**Tech Stack:** Swift/SwiftNIO (Mac), Swift/Network.framework (iOS), Markdown (smoke tests)

---

## Branch Setup

Work on branch `feature/phase-5-polish` (already created from `feature/phase-4-tailscale`).

When Phase 5 is complete and tests pass, merge to `main` with `--no-ff` and tag `v5.0-phase-5`.

---

## File Map

**Modified files:**
- `apps/mac/TermCast/WebSocket/WebSocketServer.swift` — add port-range fallback, expose bound port
- `apps/mac/TermCast/App/TermCastApp.swift` — pass preferred port from UserDefaults; save bound port after start
- `apps/ios/TermCastiOS/Views/SessionTabView.swift` — send `attach` on appear for ring buffer replay

**New files:**
- `apps/mac/TermCastTests/WebSocketServerTests.swift` — port conflict fallback tests
- `docs/context/smoke-tests.md` — manual smoke test checklist

---

### Task 1: Mac — Port conflict detection + UserDefaults persistence

**Files:**
- Modify: `apps/mac/TermCast/WebSocket/WebSocketServer.swift`
- Modify: `apps/mac/TermCast/App/TermCastApp.swift`
- Create: `apps/mac/TermCastTests/WebSocketServerTests.swift`

**Context:** The current `WebSocketServer` hardcodes port 7681 and will crash with an unhandled error if that port is occupied. The spec requires trying 7682–7685 as fallbacks and persisting the chosen port across restarts. The actor's `start()` currently returns `Void` — change it to return the bound `Int` port so the caller can save it. `TermCastApp.swift` line 58 passes `port: 7681`; change it to read `UserDefaults.standard.integer(forKey: "wsPort")` with a fallback of 7681.

`IOError` is from SwiftNIO (`NIOPosix` import, already present). The errno code for address-in-use is `EADDRINUSE` (48 on Darwin). We use `(err as? IOError)?.errnoCode == EADDRINUSE` to detect it.

- [ ] **Step 1: Write the failing tests**

Create `apps/mac/TermCastTests/WebSocketServerTests.swift`:

```swift
import Testing
import Foundation
@testable import TermCast

@Suite("WebSocketServer")
struct WebSocketServerTests {

    @Test("binds to preferred port when available")
    func bindsToPreferredPort() async throws {
        let server = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let port = try await server.start()
        #expect(port == 9681)
        try await server.stop()
    }

    @Test("falls back to next port when preferred is occupied")
    func fallsBackWhenPreferredOccupied() async throws {
        // Occupy port 9681 with a blocker server
        let blocker = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let firstPort = try await blocker.start()
        #expect(firstPort == 9681)

        // Second server with same preferred port must fall back to 9682
        let server = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let secondPort = try await server.start()
        #expect(secondPort == 9682)

        try await blocker.stop()
        try await server.stop()
    }

    @Test("throws when all ports in range are occupied")
    func throwsWhenAllPortsOccupied() async throws {
        // Occupy 9690–9694 with 5 blocker servers
        var blockers: [WebSocketServer] = []
        for port in 9690...9694 {
            let b = WebSocketServer(
                preferredPort: port,
                jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
                registry: SessionRegistry(),
                broadcaster: SessionBroadcaster()
            )
            let bound = try await b.start()
            #expect(bound == port)
            blockers.append(b)
        }

        let server = WebSocketServer(
            preferredPort: 9690,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        await #expect(throws: WebSocketServerError.noPortAvailable) {
            _ = try await server.start()
        }

        for b in blockers { try await b.stop() }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd apps/mac
xcodebuild test -scheme TermCast \
  -destination 'platform=macOS' \
  -only-testing:TermCastTests/WebSocketServerTests 2>&1 | tail -20
```
Expected: FAIL — `WebSocketServer` has no `preferredPort` parameter and `start()` returns `Void`, not `Int`.

- [ ] **Step 3: Update WebSocketServer.swift**

Replace `apps/mac/TermCast/WebSocket/WebSocketServer.swift` with:

```swift
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

enum WebSocketServerError: Error, Equatable {
    case noPortAvailable
}

actor WebSocketServer {
    private let preferredPort: Int
    private let jwtManager: JWTManager
    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var serverChannel: (any Channel)?
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    /// Number of consecutive ports to attempt before giving up.
    private static let portAttempts = 5

    init(preferredPort: Int, jwtManager: JWTManager, registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.preferredPort = preferredPort
        self.jwtManager = jwtManager
        self.registry = registry
        self.broadcaster = broadcaster
    }

    /// Starts the server, trying preferredPort then up to 4 higher ports on EADDRINUSE.
    /// Returns the port that was successfully bound.
    @discardableResult
    func start() async throws -> Int {
        let jwt = jwtManager
        let reg = registry
        let bc = broadcaster

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { [jwt] channel, head -> EventLoopFuture<HTTPHeaders?> in
                let authHeader = head.headers["Authorization"].first ?? ""
                guard authHeader.hasPrefix("Bearer "),
                      jwt.verify(String(authHeader.dropFirst(7))) else {
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ -> EventLoopFuture<Void> in
                channel.pipeline.addHandler(WebSocketHandler(registry: reg, broadcaster: bc))
            }
        )

        let upgradeConfig = NIOHTTPServerUpgradeConfiguration(
            upgraders: [upgrader],
            completionHandler: { _ in }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfig)
            }

        for offset in 0..<Self.portAttempts {
            let port = preferredPort + offset
            do {
                serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
                return port
            } catch let err as IOError where err.errnoCode == EADDRINUSE {
                continue
            }
        }
        throw WebSocketServerError.noPortAvailable
    }

    func stop() async throws {
        try await serverChannel?.close().get()
        try await group.shutdownGracefully()
    }
}
```

- [ ] **Step 4: Update TermCastApp.swift — use UserDefaults for port**

In `apps/mac/TermCast/App/TermCastApp.swift`, replace the WebSocket server startup block (lines 57–75):

```swift
        // 5. Start WebSocket server
        let preferredPort = UserDefaults.standard.integer(forKey: "wsPort").nonZeroOr(default: 7681)
        wsServer = WebSocketServer(
            preferredPort: preferredPort,
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
                let boundPort = try await ws.start()
                UserDefaults.standard.set(boundPort, forKey: "wsPort")
            } catch {
                fputs("TermCast: failed to start servers: \(error)\n", stderr)
            }
        }
```

Add this private extension at the bottom of `TermCastApp.swift`, before the final closing brace:

```swift
private extension Int {
    func nonZeroOr(default fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd apps/mac
xcodebuild test -scheme TermCast \
  -destination 'platform=macOS' \
  -only-testing:TermCastTests/WebSocketServerTests 2>&1 | tail -20
```
Expected: 3 tests pass — `bindsToPreferredPort`, `fallsBackWhenPreferredOccupied`, `throwsWhenAllPortsOccupied`.

- [ ] **Step 6: Full Mac test suite to check no regressions**

```bash
cd apps/mac
xcodebuild test -scheme TermCast \
  -destination 'platform=macOS' 2>&1 | grep -E "(Test.*passed|Test.*failed|BUILD)" | tail -20
```
Expected: all tests pass, BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add apps/mac/TermCast/WebSocket/WebSocketServer.swift \
        apps/mac/TermCast/App/TermCastApp.swift \
        apps/mac/TermCastTests/WebSocketServerTests.swift
git commit -m "feat(mac): port conflict detection — fallback 7681→7685, persist in UserDefaults"
```

---

### Task 2: iOS — Ring buffer replay via attach on session open

**Files:**
- Modify: `apps/ios/TermCastiOS/Views/SessionTabView.swift`
- Modify: `apps/ios/TermCastiOSTests/WSMessageiOSTests.swift` (add `attach` message test)

**Context:** When an iOS client connects to the Mac, the Mac's `WebSocketHandler.channelActive` immediately sends a `sessions` message listing all open sessions. The iOS client shows these sessions in `SessionListView`. When the user taps a session, `SessionTabView` appears — but it never sends an `attach` message to the Mac. Without `attach`, `WebSocketHandler` never calls `pty.bufferSnapshot()`, so the terminal shows blank until new output arrives. The fix is a single `.onAppear` in `SessionTabView` that sends `WSMessage.attach(sessionId: session.id)`.

`WSMessage.attach(sessionId:)` is already defined in `apps/ios/TermCastiOS/Models/WSMessage.swift` — no model changes needed.

The existing `WSMessageiOSTests.swift` tests input/output message construction. Add a test for `attach` there.

- [ ] **Step 1: Write the failing test**

In `apps/ios/TermCastiOSTests/WSMessageiOSTests.swift`, append after the last existing `@Test`:

```swift
@Test("attach message encodes sessionId correctly")
func attachMessageEncodesSessionId() {
    let id = UUID(uuidString: "AABBCCDD-1234-5678-ABCD-000000000001")!
    let msg = WSMessage.attach(sessionId: id)
    #expect(msg.type == .attach)
    #expect(msg.sessionId == "AABBCCDD-1234-5678-ABCD-000000000001")
    let json = msg.json()
    #expect(json.contains("\"attach\""))
    #expect(json.contains("AABBCCDD-1234-5678-ABCD-000000000001"))
}
```

- [ ] **Step 2: Run test to verify it fails or the type is missing**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TermCastiOSTests/WSMessageiOSTests 2>&1 | tail -20
```
Expected: PASS if `attach` is already in the enum (it is — `case attach, input, pong` in WSMessage.swift), or the new test runs and passes. This is a green-from-the-start test that confirms the message type exists.

- [ ] **Step 3: Add attach on appear to SessionTabView**

Replace `apps/ios/TermCastiOS/Views/SessionTabView.swift` with:

```swift
// apps/ios/TermCastiOS/Views/SessionTabView.swift
import SwiftUI

struct SessionTabView: View {
    let session: Session
    let wsClient: WSClient
    @State private var pendingOutput: Data?
    @State private var isEnded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TerminalView(
                sessionId: session.id,
                pendingOutput: $pendingOutput,
                onInput: { bytes in
                    wsClient.send(.input(sessionId: session.id, bytes: bytes))
                },
                onResize: { cols, rows in
                    wsClient.send(.resize(sessionId: session.id, cols: cols, rows: rows))
                }
            )
            .ignoresSafeArea()

            if isEnded {
                VStack {
                    HStack {
                        Spacer()
                        Text("Session ended")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Request ring buffer replay — Mac replays the last 64KB of output
            // so the terminal isn't blank when the view first appears.
            wsClient.send(.attach(sessionId: session.id))
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .termcastOutput(session.id))
        ) { notif in
            if let data = notif.userInfo?["data"] as? Data {
                pendingOutput = data
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .termcastSessionEnded(session.id))
        ) { _ in
            isEnded = true
        }
        .navigationTitle("\(session.termApp) — \(session.shell)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static func termcastOutput(_ id: SessionID) -> Notification.Name {
        Notification.Name("termcast.output.\(id.uuidString)")
    }
    static func termcastSessionEnded(_ id: SessionID) -> Notification.Name {
        Notification.Name("termcast.sessionEnded.\(id.uuidString)")
    }
}
```

- [ ] **Step 4: Build to verify**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \
  | grep -E "(error:|BUILD)" | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Run all iOS tests to verify no regressions**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \
  | grep -E "(Test.*passed|Test.*failed|BUILD)" | tail -20
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add apps/ios/TermCastiOS/Views/SessionTabView.swift \
        apps/ios/TermCastiOSTests/WSMessageiOSTests.swift
git commit -m "feat(ios): send attach on session open — triggers ring buffer replay from Mac"
```

---

### Task 3: Smoke test documentation

**Files:**
- Create: `docs/context/smoke-tests.md`

**Context:** `docs/context/STATUS.md` references `docs/context/smoke-tests.md` as the manual test protocol created in Phase 5. The spec says no cross-device E2E tests exist — this checklist is the manual substitute. It covers the full user journey from install to bidirectional terminal output.

- [ ] **Step 1: Create the smoke test document**

Create `docs/context/smoke-tests.md`:

```markdown
# TermCast — Manual Smoke Test Protocol

**Purpose:** End-to-end verification that cannot be automated (requires real Tailscale, real Mac PTY, real phone).  
**Run before:** Every release merge, after any change to Mac WebSocket server or shell integration.

---

## Prerequisites

- Mac running macOS 14+ with TermCast built and running
- Tailscale installed and authenticated on the Mac
- iOS simulator or real device with TermCastiOS installed
- Android emulator or real device with TermCast Android installed
- Both mobile clients on Tailscale (or on same LAN with Tailscale routing)

---

## Smoke Test 1 — First Launch + Pairing (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Fresh install: delete app, delete Keychain entry for `jwt-secret`, relaunch TermCast | QR code window appears |
| 2 | Open iOS app (no stored credentials) | QR scan screen appears |
| 3 | Scan QR code with iOS app | iOS navigates to session list |
| 4 | Open a terminal on Mac (`zsh` or `bash` session) | Session appears in iOS session list within 2 seconds |
| 5 | Tap session in iOS app | Terminal view opens; last 64KB of output is replayed (ring buffer) |
| 6 | Type a command in the iOS keyboard toolbar | Command appears in Mac terminal |
| 7 | Run a long command on Mac (e.g. `ls -la /usr/bin`) | Output scrolls in iOS terminal view |

---

## Smoke Test 2 — First Launch + Pairing (Android)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Fresh install Android app | QR scan screen appears |
| 2 | Scan QR code from Mac menu bar ("Pair another device…") | Android navigates to session list |
| 3 | Tap session | xterm.js WebView renders terminal output |
| 4 | Type from Android soft keyboard | Input arrives in Mac terminal |

---

## Smoke Test 3 — Reconnect + Ring Buffer Replay

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS app connected, session open | Terminal shows live output |
| 2 | Put iOS app in background for 30+ seconds | App stays alive; NWConnection times out |
| 3 | Bring iOS app back to foreground | OfflineView appears briefly, then reconnects |
| 4 | Tap session again | Ring buffer replayed — history visible, not blank |

---

## Smoke Test 4 — Auth Failure Re-pairing (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS connected | Session list visible |
| 2 | On Mac: delete Keychain entry and relaunch TermCast (new JWT secret generated) | iOS shows OfflineView with "Unpair — Scan QR again" button |
| 3 | Tap "Unpair — Scan QR again" | QR scan screen appears |
| 4 | Scan new QR code | iOS reconnects and shows session list |

---

## Smoke Test 5 — Auth Failure Re-pairing (Android)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Android connected | Session list visible |
| 2 | On Mac: delete Keychain entry and relaunch TermCast | Android automatically clears credentials and shows QR scan screen |
| 3 | Scan new QR code | Android reconnects |

---

## Smoke Test 6 — Port Conflict Recovery

| Step | Action | Expected |
|------|--------|----------|
| 1 | Pre-occupy port 7681: `nc -l 7681 &` in a Mac terminal | Port in use |
| 2 | Launch TermCast | App starts without error; server binds to 7682 |
| 3 | Verify in Console.app or `lsof -i :7682` | TermCast process listening on 7682 |
| 4 | Kill the nc process, relaunch TermCast | App starts on 7681 again (UserDefaults persists last port, but falls back to 7681 when 7682 was last used and 7681 is now free) |

---

## Smoke Test 7 — Session Ended Banner

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS app open with active session tab | Terminal shows live output |
| 2 | On Mac: `exit` in the terminal session | iOS shows red "Session ended" banner in top-right of terminal view |
| 3 | History remains visible below the banner | Terminal output is not cleared |

---

## Smoke Test 8 — Multi-session

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open 3 terminal sessions on Mac | iOS session list shows all 3 |
| 2 | Tap each session | Each has independent terminal history |
| 3 | Type in each session | Input reaches the correct Mac terminal |
| 4 | Close one session on Mac | That session's tab shows "Session ended"; others unaffected |

---

## Smoke Test 9 — Mac Restart Recovery

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open 2 terminal sessions, connect iOS | Both sessions visible |
| 2 | Kill TermCast process (Cmd+Q or force quit) | iOS shows OfflineView |
| 3 | Relaunch TermCast | TermCast re-scans `/tmp/termcast/` for live sessions |
| 4 | iOS reconnects automatically | Both sessions restored in session list |

---

## Pass Criteria

All 9 smoke tests pass without error. No crash logs in Console.app. iOS and Android apps do not show unexpected blank screens or stuck states.
```

- [ ] **Step 2: Commit**

```bash
git add docs/context/smoke-tests.md
git commit -m "docs: add manual smoke test protocol (9 tests, full user journey)"
```

---

### Task 4: Merge Phase 5 to main

- [ ] **Step 1: Update STATUS.md**

In `docs/context/STATUS.md`, update:
- Phase 5 row: change `Pending` to `Complete — merging to main`
- `Current Phase` header: `Complete — Phase 5 (polish + error states)`
- `Branch:` line: `feature/phase-5-polish (merging → main)`
- `Current Session Focus` section: describe Phase 5 completion

- [ ] **Step 2: Commit STATUS.md**

```bash
git add docs/context/STATUS.md
git commit -m "docs: mark Phase 5 complete — polish, port conflict, ring buffer replay, smoke tests"
```

- [ ] **Step 3: Merge to main and tag**

```bash
# From repo root (not worktree):
cd /Users/himanshu/Desktop/struggle/termcast
git checkout main
git merge --no-ff feature/phase-5-polish \
  -m "chore: merge Phase 5 — port conflict detection, ring buffer replay, smoke tests"
git tag v5.0-phase-5
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|-------------|------|
| Mac: port 7681 in use → increment to 7682, persist in UserDefaults | T1 |
| iOS: ring buffer replay on attach (reconnect → client catches up) | T2 |
| Smoke test protocol in `docs/context/smoke-tests.md` | T3 |
| Session ended banner (already implemented in Phase 2–3) | — |
| Mac crash restart recovery (already implemented) | — |

### Placeholder Scan

No TBD, TODO, or "implement later" patterns. All steps have complete code.

### Type Consistency

- `WebSocketServer.init(preferredPort:jwtManager:registry:broadcaster:)` — defined in T1 step 3, used in T1 step 4 and T1 tests ✅
- `WebSocketServerError.noPortAvailable` — defined in T1 step 3, tested in T1 step 1 ✅
- `WSMessage.attach(sessionId:)` — already defined in `WSMessage.swift`, tested in T2 step 1, called in T2 step 3 ✅
- `Int.nonZeroOr(default:)` — defined in T1 step 4, used in same step ✅
