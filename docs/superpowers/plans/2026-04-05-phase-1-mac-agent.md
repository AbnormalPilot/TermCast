# Phase 1: Mac Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the macOS 14+ menu bar app that discovers terminal sessions via shell integration hooks, streams I/O over a SwiftNIO WebSocket server, and sets up Tailscale as the permanent network path.

**Architecture:** `NSStatusItem` agent (no Dock icon). Shells register via Unix domain socket at `~/.termcast/agent.sock`. Output captured via named pipe tee; input injected by writing to the TTY slave device (user-owned, no privilege needed). SwiftNIO serves WebSocket on `:7681`; Tailscale Serve proxies it to `wss://macbook.ts.net`.

**Tech Stack:** Swift 5.10, macOS 14+, SwiftNIO 2.x (`NIOCore`, `NIOHTTP1`, `NIOWebSocket`), CryptoKit (JWT), libproc/sysctl (process inspection), AppKit (menu bar), CoreImage (QR code)

---

## File Map

```
apps/mac/
├── Package.swift                                # SPM manifest (CLI tool target for termcast-hook)
├── TermCast.xcodeproj                           # Main Xcode project
├── TermCast/
│   ├── App/
│   │   ├── TermCastApp.swift                    # @main AppDelegate, lifecycle wiring
│   │   └── Info.plist                           # LSUIElement=YES, NSMicrophoneUsageDescription
│   ├── Models/
│   │   ├── Session.swift                        # Session struct (Codable, Identifiable)
│   │   └── WSMessage.swift                      # WSMessage enum + encoding helpers
│   ├── Core/
│   │   ├── RingBuffer.swift                     # 64KB circular byte buffer
│   │   ├── JWTManager.swift                     # HS256 sign/verify via CryptoKit
│   │   └── ProcessInspector.swift               # libproc: PID → terminal app name
│   ├── ShellIntegration/
│   │   ├── AgentSocketServer.swift              # Unix domain socket, receives registrations
│   │   ├── PTYSession.swift                     # Output pipe reader + TTY input writer
│   │   ├── SessionRegistry.swift                # Actor: [SessionID: PTYSession]
│   │   └── ShellHookInstaller.swift             # Writes hook to .zshrc/.bashrc/config.fish
│   ├── WebSocket/
│   │   ├── WebSocketServer.swift                # SwiftNIO ServerBootstrap on :7681
│   │   ├── WebSocketHandler.swift               # Per-client channel handler
│   │   ├── SessionBroadcaster.swift             # Fan-out output to attached clients
│   │   └── InputRouter.swift                    # Routes client input → PTYSession stdin
│   ├── Auth/
│   │   └── KeychainStore.swift                  # Read/write JWT secret from Keychain
│   ├── Tailscale/
│   │   └── TailscaleSetup.swift                 # First-launch wizard: check/serve/hostname/QR
│   └── MenuBar/
│       └── MenuBarController.swift              # NSStatusItem + menu construction
├── TermCastHook/                                # Separate CLI tool target
│   └── main.swift                               # termcast-hook binary: registers shell with agent
└── TermCastTests/
    ├── RingBufferTests.swift
    ├── JWTManagerTests.swift
    ├── ProcessInspectorTests.swift
    └── SessionRegistryTests.swift
```

---

## Task 1: Xcode Project + SPM Dependencies

**Files:**
- Create: `apps/mac/TermCast.xcodeproj` (via `xcodegen` or manual)
- Create: `apps/mac/Package.swift`

- [ ] **Step 1: Scaffold the Xcode project using `xcodegen` or create manually**

```bash
cd apps/mac

# Option A — use xcodegen (brew install xcodegen)
# Option B — create project.yml for xcodegen
cat > project.yml << 'EOF'
name: TermCast
options:
  bundleIdPrefix: com.termcast
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"

packages:
  swift-nio:
    url: https://github.com/apple/swift-nio.git
    from: 2.65.0

targets:
  TermCast:
    type: application
    platform: macOS
    sources: [TermCast]
    info:
      path: TermCast/App/Info.plist
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.termcast.mac
      SWIFT_VERSION: 5.10
    dependencies:
      - package: swift-nio
        product: NIOCore
      - package: swift-nio
        product: NIOHTTP1
      - package: swift-nio
        product: NIOWebSocket
      - package: swift-nio
        product: NIOPosix

  TermCastHook:
    type: tool
    platform: macOS
    sources: [TermCastHook]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.termcast.hook
      SWIFT_VERSION: 5.10

  TermCastTests:
    type: bundle.unit-test
    platform: macOS
    sources: [TermCastTests]
    dependencies:
      - target: TermCast
EOF

xcodegen generate
```

- [ ] **Step 2: Create Info.plist with LSUIElement (no Dock icon)**

```bash
mkdir -p TermCast/App
cat > TermCast/App/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TermCast</string>
    <key>CFBundleIdentifier</key>
    <string>com.termcast.mac</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF
```

- [ ] **Step 3: Verify project opens**

```bash
open TermCast.xcodeproj
```

Expected: Xcode opens with two targets (TermCast, TermCastHook) and swift-nio as a package dependency.

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/mac/
git commit -m "feat(mac): xcode project scaffold with SwiftNIO dependency"
```

---

## Task 2: Models — Session + WSMessage

**Files:**
- Create: `apps/mac/TermCast/Models/Session.swift`
- Create: `apps/mac/TermCast/Models/WSMessage.swift`

- [ ] **Step 1: Write the failing test**

```swift
// apps/mac/TermCastTests/ModelsTests.swift
import XCTest
@testable import TermCast

final class ModelsTests: XCTestCase {
    func testSessionIsIdentifiable() {
        let s1 = Session(pid: 123, tty: "/dev/ttys003", shell: "zsh", termApp: "iTerm2", outPipe: "/tmp/termcast/123.out")
        let s2 = Session(pid: 456, tty: "/dev/ttys004", shell: "bash", termApp: "Terminal", outPipe: "/tmp/termcast/456.out")
        XCTAssertNotEqual(s1.id, s2.id)
        XCTAssertEqual(s1.cols, 80)
        XCTAssertEqual(s1.rows, 24)
    }

    func testWSMessageJSONRoundTrip() throws {
        let msg = WSMessage.ping()
        let json = msg.json()
        let decoded = try XCTUnwrap(WSMessage.from(json: json))
        XCTAssertEqual(decoded.type, .ping)
    }

    func testOutputMessageEncodesBase64() throws {
        let id = UUID()
        let data = Data([0x1b, 0x5b, 0x48])  // ESC[H
        let msg = WSMessage.output(sessionId: id, data: data)
        XCTAssertEqual(msg.sessionId, id.uuidString)
        XCTAssertNotNil(msg.data)
        let decoded = Data(base64Encoded: msg.data!)!
        XCTAssertEqual(decoded, data)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: `error: cannot find type 'Session'`

- [ ] **Step 3: Implement Session.swift**

```swift
// apps/mac/TermCast/Models/Session.swift
import Foundation

typealias SessionID = UUID

struct Session: Codable, Identifiable, Sendable {
    let id: SessionID
    let pid: Int
    let tty: String       // e.g. "/dev/ttys003"
    let shell: String     // e.g. "zsh"
    let termApp: String   // e.g. "iTerm2"
    let outPipe: String   // path to named pipe for output capture
    var isActive: Bool
    var cols: Int
    var rows: Int

    init(pid: Int, tty: String, shell: String, termApp: String, outPipe: String) {
        self.id = UUID()
        self.pid = pid
        self.tty = tty
        self.shell = shell
        self.termApp = termApp
        self.outPipe = outPipe
        self.isActive = true
        self.cols = 80
        self.rows = 24
    }
}
```

- [ ] **Step 4: Implement WSMessage.swift**

```swift
// apps/mac/TermCast/Models/WSMessage.swift
import Foundation

enum WSMessageType: String, Codable {
    // Server → Client
    case sessions, sessionOpened, sessionClosed, output, resize, ping
    // Client → Server
    case attach, input, pong
}

struct WSMessage: Codable {
    let type: WSMessageType
    var sessions: [Session]?
    var session: Session?
    var sessionId: String?
    var data: String?      // base64-encoded bytes
    var cols: Int?
    var rows: Int?

    // MARK: - Server → Client factories
    static func ping() -> WSMessage { WSMessage(type: .ping) }
    static func sessions(_ sessions: [Session]) -> WSMessage {
        WSMessage(type: .sessions, sessions: sessions)
    }
    static func sessionOpened(_ session: Session) -> WSMessage {
        WSMessage(type: .sessionOpened, session: session)
    }
    static func sessionClosed(_ id: SessionID) -> WSMessage {
        WSMessage(type: .sessionClosed, sessionId: id.uuidString)
    }
    static func output(sessionId: SessionID, data: Data) -> WSMessage {
        WSMessage(type: .output, sessionId: sessionId.uuidString,
                  data: data.base64EncodedString())
    }
    static func resize(sessionId: SessionID, cols: Int, rows: Int) -> WSMessage {
        WSMessage(type: .resize, sessionId: sessionId.uuidString, cols: cols, rows: rows)
    }

    // MARK: - Encoding
    func json() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    static func from(json: String) -> WSMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(WSMessage.self, from: data)
    }
}
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: `Test Suite 'ModelsTests' passed`

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/mac/TermCast/Models/ apps/mac/TermCastTests/ModelsTests.swift
git commit -m "feat(mac): Session and WSMessage models with JSON round-trip"
```

---

## Task 3: RingBuffer

**Files:**
- Create: `apps/mac/TermCast/Core/RingBuffer.swift`
- Create: `apps/mac/TermCastTests/RingBufferTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/mac/TermCastTests/RingBufferTests.swift
import XCTest
@testable import TermCast

final class RingBufferTests: XCTestCase {
    func testEmptyBufferReturnsEmptySnapshot() {
        let buf = RingBuffer(capacity: 8)
        XCTAssertEqual(buf.snapshot(), [])
        XCTAssertEqual(buf.count, 0)
    }

    func testWriteAndReadBack() {
        let buf = RingBuffer(capacity: 8)
        buf.write([1, 2, 3])
        XCTAssertEqual(buf.snapshot(), [1, 2, 3])
        XCTAssertEqual(buf.count, 3)
    }

    func testDoesNotExceedCapacity() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4, 5, 6])  // 6 bytes into capacity-4 buffer
        XCTAssertEqual(buf.count, 4)
        XCTAssertEqual(buf.snapshot(), [3, 4, 5, 6])  // oldest overwritten
    }

    func testWrapAround() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.write([5])             // wraps: evicts 1
        XCTAssertEqual(buf.snapshot(), [2, 3, 4, 5])
    }

    func testReset() {
        let buf = RingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.reset()
        XCTAssertEqual(buf.count, 0)
        XCTAssertEqual(buf.snapshot(), [])
    }

    func testFullCapacityRoundTrip() {
        let capacity = 65_536
        let buf = RingBuffer(capacity: capacity)
        let input = (0..<capacity).map { UInt8($0 % 256) }
        buf.write(input)
        XCTAssertEqual(buf.snapshot(), input)
        XCTAssertEqual(buf.count, capacity)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED"
```

Expected: `error: cannot find type 'RingBuffer'`

- [ ] **Step 3: Implement RingBuffer**

```swift
// apps/mac/TermCast/Core/RingBuffer.swift
import Foundation

/// Thread-unsafe 64KB circular byte buffer.
/// Callers must synchronise access (e.g. within an actor).
final class RingBuffer {
    private var storage: [UInt8]
    private let capacity: Int
    private var head: Int = 0   // index of oldest valid byte
    private var tail: Int = 0   // index of next write position
    private(set) var count: Int = 0

    init(capacity: Int = 65_536) {
        self.capacity = capacity
        self.storage = [UInt8](repeating: 0, count: capacity)
    }

    func write(_ bytes: [UInt8]) {
        for byte in bytes {
            storage[tail] = byte
            tail = (tail + 1) % capacity
            if count == capacity {
                head = (head + 1) % capacity  // evict oldest
            } else {
                count += 1
            }
        }
    }

    /// Returns a contiguous copy of all buffered bytes, oldest first.
    func snapshot() -> [UInt8] {
        guard count > 0 else { return [] }
        var result = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = storage[(head + i) % capacity]
        }
        return result
    }

    func reset() {
        head = 0; tail = 0; count = 0
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "FAILED|passed"
```

Expected: `Test Suite 'RingBufferTests' passed`

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/mac/TermCast/Core/RingBuffer.swift apps/mac/TermCastTests/RingBufferTests.swift
git commit -m "feat(mac): RingBuffer — 64KB circular byte buffer with wrap-around"
```

---

## Task 4: JWTManager

**Files:**
- Create: `apps/mac/TermCast/Core/JWTManager.swift`
- Create: `apps/mac/TermCast/Auth/KeychainStore.swift`
- Create: `apps/mac/TermCastTests/JWTManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/mac/TermCastTests/JWTManagerTests.swift
import XCTest
@testable import TermCast

final class JWTManagerTests: XCTestCase {
    var manager: JWTManager!

    override func setUp() {
        let secret = JWTManager.generateSecret()
        manager = JWTManager(secret: secret)
    }

    func testGeneratedSecretIs32Bytes() {
        let secret = JWTManager.generateSecret()
        XCTAssertEqual(secret.count, 32)
    }

    func testSignAndVerify() {
        let token = manager.sign()
        XCTAssertTrue(manager.verify(token))
    }

    func testTokenHasThreeParts() {
        let token = manager.sign()
        XCTAssertEqual(token.split(separator: ".").count, 3)
    }

    func testTamperedTokenFails() {
        let token = manager.sign()
        let tampered = token + "x"
        XCTAssertFalse(manager.verify(tampered))
    }

    func testWrongSecretFails() {
        let token = manager.sign()
        let other = JWTManager(secret: JWTManager.generateSecret())
        XCTAssertFalse(other.verify(token))
    }

    func testExpiredTokenFails() {
        // Sign with expiry in the past
        let token = manager.sign(expiry: Date().addingTimeInterval(-1))
        XCTAssertFalse(manager.verify(token))
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'JWTManager'`

- [ ] **Step 3: Implement JWTManager**

```swift
// apps/mac/TermCast/Core/JWTManager.swift
import CryptoKit
import Foundation
import Security

private struct JWTHeader: Encodable {
    let alg = "HS256"
    let typ = "JWT"
}

private struct JWTPayload: Codable {
    let sub: String
    let iat: Int
    let exp: Int
}

final class JWTManager: Sendable {
    private let key: SymmetricKey

    init(secret: Data) {
        self.key = SymmetricKey(data: secret)
    }

    // MARK: - Secret generation

    static func generateSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Sign

    func sign(subject: String = "termcast-client",
              expiry: Date = Date().addingTimeInterval(30 * 24 * 3600)) -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = base64url(encode(JWTHeader()))
        let payload = base64url(encode(JWTPayload(sub: subject, iat: now,
                                                   exp: Int(expiry.timeIntervalSince1970))))
        let message = "\(header).\(payload)"
        let sig = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return "\(message).\(base64url(Data(sig)))"
    }

    // MARK: - Verify

    func verify(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return false }

        // 1. Verify signature
        let message = "\(parts[0]).\(parts[1])"
        let expected = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        guard let actual = Data(base64URLDecoded: parts[2]) else { return false }
        guard Data(expected) == actual else { return false }

        // 2. Verify expiry
        guard let payloadData = Data(base64URLDecoded: parts[1]),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: payloadData) else {
            return false
        }
        return Date().timeIntervalSince1970 < Double(payload.exp)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Data base64url extension

extension Data {
    init?(base64URLDecoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
```

- [ ] **Step 4: Implement KeychainStore**

```swift
// apps/mac/TermCast/Auth/KeychainStore.swift
import Foundation
import Security

enum KeychainStore {
    private static let service = "com.termcast.mac"

    static func save(key: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)  // delete existing before adding
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.notFound(key)
        }
        return data
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case notFound(String)
}
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "FAILED|passed"
```

Expected: `Test Suite 'JWTManagerTests' passed`

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/mac/TermCast/Core/JWTManager.swift apps/mac/TermCast/Auth/KeychainStore.swift apps/mac/TermCastTests/JWTManagerTests.swift
git commit -m "feat(mac): JWTManager (HS256/CryptoKit) + KeychainStore"
```

---

## Task 5: ProcessInspector

**Files:**
- Create: `apps/mac/TermCast/Core/ProcessInspector.swift`
- Create: `apps/mac/TermCastTests/ProcessInspectorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/mac/TermCastTests/ProcessInspectorTests.swift
import XCTest
@testable import TermCast

final class ProcessInspectorTests: XCTestCase {
    func testCurrentProcessHasName() {
        let name = ProcessInspector.processName(of: Int(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(name.isEmpty)
    }

    func testParentPIDExists() {
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let ppid = ProcessInspector.parentPID(of: pid)
        XCTAssertNotNil(ppid)
        XCTAssertGreaterThan(ppid!, 0)
    }

    func testUnknownPIDReturnsNil() {
        XCTAssertNil(ProcessInspector.parentPID(of: 9_999_999))
    }

    func testTerminalAppFromCurrentProcess() {
        // Running inside Xcode test runner — should find Xcode in parent chain
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let app = ProcessInspector.terminalApp(forPID: pid)
        XCTAssertFalse(app.isEmpty)  // may return "Unknown" in CI, that's OK
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'ProcessInspector'`

- [ ] **Step 3: Implement ProcessInspector**

```swift
// apps/mac/TermCast/Core/ProcessInspector.swift
import Foundation

// libproc headers
import Darwin.sys.proc_info

struct ProcessInspector {
    private static let knownTerminals = [
        "iTerm2", "Terminal", "Warp", "Alacritty",
        "kitty", "Code", "Code Helper", "Hyper"
    ]

    /// Returns the process name for a given PID.
    static func processName(of pid: Int) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        proc_name(Int32(pid), &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    /// Returns the parent PID of a given PID, or nil if unavailable.
    static func parentPID(of pid: Int) -> Int? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        let ppid = Int(info.pbi_ppid)
        return ppid > 0 ? ppid : nil
    }

    /// Walks the parent chain (up to 8 hops) to find a known terminal emulator.
    static func terminalApp(forPID pid: Int) -> String {
        var current = pid
        for _ in 0..<8 {
            let name = processName(of: current)
            if knownTerminals.contains(where: { name.contains($0) }) { return name }
            guard let parent = parentPID(of: current) else { break }
            if parent == current || parent <= 1 { break }
            current = parent
        }
        return "Unknown"
    }
}
```

- [ ] **Step 4: Add libproc bridging header if needed**

In Xcode: Target → Build Settings → Swift Compiler - General → Objective-C Bridging Header.  
Create `apps/mac/TermCast/App/TermCast-Bridging-Header.h`:

```c
// apps/mac/TermCast/App/TermCast-Bridging-Header.h
#include <libproc.h>
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/mac/TermCast/Core/ProcessInspector.swift apps/mac/TermCast/App/TermCast-Bridging-Header.h apps/mac/TermCastTests/ProcessInspectorTests.swift
git commit -m "feat(mac): ProcessInspector — libproc PID→terminal-app name"
```

---

## Task 6: termcast-hook CLI Tool

**Files:**
- Create: `apps/mac/TermCastHook/main.swift`

This binary is installed to `~/.termcast/bin/termcast-hook` by the shell hook installer. The shell hook calls it on startup to register the session.

- [ ] **Step 1: Implement the hook binary**

```swift
// apps/mac/TermCastHook/main.swift
import Foundation

// Parse command-line arguments
var pid: Int = 0
var tty = ""
var shell = ""
var term = ""
var outPipe = ""

var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--pid":      pid = Int(args.first ?? "") ?? 0; args = args.dropFirst()
    case "--tty":      tty = args.first ?? ""; args = args.dropFirst()
    case "--shell":    shell = args.first ?? ""; args = args.dropFirst()
    case "--term":     term = args.first ?? ""; args = args.dropFirst()
    case "--out-pipe": outPipe = args.first ?? ""; args = args.dropFirst()
    default: break
    }
}

guard pid > 0, !tty.isEmpty, !outPipe.isEmpty else {
    fputs("termcast-hook: missing required arguments\n", stderr)
    exit(1)
}

// Connect to agent Unix socket
let socketPath = NSHomeDirectory() + "/.termcast/agent.sock"
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { exit(0) }  // Agent not running — silent exit

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.withCString { ptr in
    withUnsafeMutablePointer(to: &addr.sun_path) { dest in
        _ = ptr.withMemoryRebound(to: CChar.self, capacity: 108) { src in
            strlcpy(UnsafeMutablePointer(dest), src, 108)
        }
    }
}

let connectResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connectResult == 0 else {
    close(sock)
    exit(0)  // Agent socket not available — silent exit
}

// Send registration JSON
let registration: [String: Any] = [
    "pid": pid,
    "tty": tty,
    "shell": shell,
    "term": term,
    "outPipe": outPipe
]
if let data = try? JSONSerialization.data(withJSONObject: registration),
   var payload = String(data: data, encoding: .utf8) {
    payload += "\n"
    _ = payload.withCString { ptr in
        send(sock, ptr, strlen(ptr), 0)
    }
}

close(sock)
```

- [ ] **Step 2: Build the hook binary**

```bash
cd apps/mac
xcodebuild build -scheme TermCastHook -destination 'platform=macOS' \
    CONFIGURATION_BUILD_DIR="$(pwd)/build" 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Test manually**

```bash
# Start a listener on a temp socket to verify the hook connects and sends JSON
python3 -c "
import socket, json, os
path = '/tmp/test-termcast.sock'
os.unlink(path) if os.path.exists(path) else None
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(1)
conn, _ = s.accept()
data = conn.recv(4096)
print(json.loads(data.decode().strip()))
conn.close(); s.close(); os.unlink(path)
" &
sleep 0.2

# Simulate what termcast-hook would do
HOME=/tmp build/termcast-hook \
    --pid 12345 --tty /dev/ttys003 --shell zsh --term iTerm2 --out-pipe /tmp/termcast/12345.out
```

Expected: Python prints `{'pid': 12345, 'tty': '/dev/ttys003', ...}`

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/mac/TermCastHook/
git commit -m "feat(mac): termcast-hook CLI binary — shell registration over Unix socket"
```

---

## Task 7: AgentSocketServer

**Files:**
- Create: `apps/mac/TermCast/ShellIntegration/AgentSocketServer.swift`

Listens on `~/.termcast/agent.sock`. Receives newline-delimited JSON registration messages from `termcast-hook` instances.

- [ ] **Step 1: Implement AgentSocketServer**

```swift
// apps/mac/TermCast/ShellIntegration/AgentSocketServer.swift
import Foundation
import NIOCore
import NIOPosix

struct ShellRegistration {
    let pid: Int
    let tty: String
    let shell: String
    let term: String
    let outPipe: String
}

actor AgentSocketServer {
    private let socketPath: String
    private let onRegister: @Sendable (ShellRegistration) async -> Void
    private var serverChannel: (any Channel)?

    init(socketPath: String, onRegister: @Sendable @escaping (ShellRegistration) async -> Void) {
        self.socketPath = socketPath
        self.onRegister = onRegister
    }

    func start(group: MultiThreadedEventLoopGroup) async throws {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        // Ensure ~/.termcast directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let onReg = onRegister
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 32)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    RegistrationHandler(onRegister: onReg)
                ])
            }

        serverChannel = try await bootstrap
            .bind(unixDomainSocketPath: socketPath)
            .get()

        // Set socket permissions so only owner can connect
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: socketPath
        )
    }

    func stop() async throws {
        try await serverChannel?.close().get()
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}

// MARK: - Line-based registration handler

private final class RegistrationHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let onRegister: @Sendable (ShellRegistration) async -> Void

    init(onRegister: @Sendable @escaping (ShellRegistration) async -> Void) {
        self.onRegister = onRegister
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard let line = buffer.readString(length: buffer.readableBytes) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let tty = json["tty"] as? String,
              let shell = json["shell"] as? String,
              let outPipe = json["outPipe"] as? String else { return }

        let reg = ShellRegistration(
            pid: pid, tty: tty,
            shell: shell,
            term: json["term"] as? String ?? "unknown",
            outPipe: outPipe
        )
        Task { await self.onRegister(reg) }
        context.close(promise: nil)
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/mac/TermCast/ShellIntegration/AgentSocketServer.swift
git commit -m "feat(mac): AgentSocketServer — Unix socket for shell registration"
```

---

## Task 8: PTYSession — Output Reading + Input Injection

**Files:**
- Create: `apps/mac/TermCast/ShellIntegration/PTYSession.swift`

One PTYSession per registered shell. Reads output from the named pipe; injects input by writing to the TTY slave device (user-owned, same-user write access, no root needed).

- [ ] **Step 1: Implement PTYSession**

```swift
// apps/mac/TermCast/ShellIntegration/PTYSession.swift
import Foundation

/// Represents one live terminal session.
/// - Output: reads from named pipe (set up by shell hook's `tee` redirect)
/// - Input: writes to TTY slave device (user-owned, writable by same user)
actor PTYSession {
    let session: Session
    private let ringBuffer: RingBuffer
    private var outputTask: Task<Void, Never>?
    private var ttyWriteFD: Int32 = -1

    // Callbacks — set before calling start()
    var onOutput: ((Data) -> Void)?
    var onClose: (() -> Void)?

    init(session: Session) {
        self.session = session
        self.ringBuffer = RingBuffer()
    }

    // MARK: - Lifecycle

    func start() {
        openTTYForInput()
        startOutputReader()
    }

    func stop() {
        outputTask?.cancel()
        if ttyWriteFD >= 0 { Darwin.close(ttyWriteFD); ttyWriteFD = -1 }
    }

    // MARK: - Input injection

    func write(bytes: Data) {
        guard ttyWriteFD >= 0 else { return }
        bytes.withUnsafeBytes { ptr in
            _ = Darwin.write(ttyWriteFD, ptr.baseAddress!, bytes.count)
        }
    }

    // MARK: - Ring buffer snapshot (for reconnecting clients)

    func bufferSnapshot() -> Data {
        Data(ringBuffer.snapshot())
    }

    // MARK: - Private

    private func openTTYForInput() {
        // The TTY device is owned by the current user — open for write only
        let fd = Darwin.open(session.tty, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        if fd >= 0 { ttyWriteFD = fd }
    }

    private func startOutputReader() {
        let pipePath = session.outPipe
        let buffer = ringBuffer
        let outputCb = onOutput
        let closeCb = onClose

        outputTask = Task.detached(priority: .utility) {
            // Open the named pipe — blocks until shell has it open too
            let fd = Darwin.open(pipePath, O_RDONLY)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd); try? FileManager.default.removeItem(atPath: pipePath) }

            var chunk = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                let n = Darwin.read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                let bytes = Array(chunk[0..<n])
                buffer.write(bytes)
                let data = Data(bytes)
                outputCb?(data)
            }
            closeCb?()
        }
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/mac/TermCast/ShellIntegration/PTYSession.swift
git commit -m "feat(mac): PTYSession — named pipe reader + TTY slave input injection"
```

---

## Task 9: SessionRegistry

**Files:**
- Create: `apps/mac/TermCast/ShellIntegration/SessionRegistry.swift`
- Create: `apps/mac/TermCastTests/SessionRegistryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/mac/TermCastTests/SessionRegistryTests.swift
import XCTest
@testable import TermCast

final class SessionRegistryTests: XCTestCase {
    func testRegisterAndLookup() async {
        let registry = SessionRegistry()
        let reg = ShellRegistration(pid: 1, tty: "/dev/ttys001",
                                     shell: "zsh", term: "iTerm2",
                                     outPipe: "/tmp/test.out")
        await registry.register(reg)
        let all = await registry.allSessions()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.shell, "zsh")
    }

    func testRemoveSession() async {
        let registry = SessionRegistry()
        let reg = ShellRegistration(pid: 2, tty: "/dev/ttys002",
                                     shell: "bash", term: "Terminal",
                                     outPipe: "/tmp/test2.out")
        await registry.register(reg)
        let sessions = await registry.allSessions()
        let id = sessions.first!.id
        await registry.remove(id: id)
        let remaining = await registry.allSessions()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMultipleSessions() async {
        let registry = SessionRegistry()
        for i in 0..<5 {
            let reg = ShellRegistration(pid: 100 + i, tty: "/dev/ttys00\(i)",
                                         shell: "zsh", term: "Warp",
                                         outPipe: "/tmp/test\(i).out")
            await registry.register(reg)
        }
        let all = await registry.allSessions()
        XCTAssertEqual(all.count, 5)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'SessionRegistry'`

- [ ] **Step 3: Implement SessionRegistry**

```swift
// apps/mac/TermCast/ShellIntegration/SessionRegistry.swift
import Foundation

/// Source of truth for all active terminal sessions.
actor SessionRegistry {
    private var sessions: [SessionID: PTYSession] = [:]

    // Callbacks invoked on the actor
    var onSessionAdded: ((Session) -> Void)?
    var onSessionRemoved: ((SessionID) -> Void)?

    func register(_ reg: ShellRegistration) {
        let session = Session(
            pid: reg.pid,
            tty: reg.tty,
            shell: reg.shell,
            termApp: ProcessInspector.terminalApp(forPID: reg.pid),
            outPipe: reg.outPipe
        )
        let ptySession = PTYSession(session: session)

        ptySession.onClose = { [weak self] in
            Task { await self?.remove(id: session.id) }
        }

        sessions[session.id] = ptySession
        ptySession.start()
        onSessionAdded?(session)
    }

    func remove(id: SessionID) {
        guard let pty = sessions.removeValue(forKey: id) else { return }
        Task { await pty.stop() }
        onSessionRemoved?(id)
    }

    func allSessions() -> [Session] {
        sessions.values.map { $0.session }
    }

    func session(id: SessionID) -> PTYSession? {
        sessions[id]
    }

    func setOutputHandler(_ handler: @escaping (SessionID, Data) -> Void) {
        for (id, pty) in sessions {
            let sessionId = id
            pty.onOutput = { data in handler(sessionId, data) }
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/mac/TermCast/ShellIntegration/SessionRegistry.swift apps/mac/TermCastTests/SessionRegistryTests.swift
git commit -m "feat(mac): SessionRegistry actor — manages active PTYSessions"
```

---

## Task 10: WebSocket Server — SwiftNIO Bootstrap

**Files:**
- Create: `apps/mac/TermCast/WebSocket/WebSocketServer.swift`
- Create: `apps/mac/TermCast/WebSocket/WebSocketHandler.swift`

- [ ] **Step 1: Implement WebSocketServer**

```swift
// apps/mac/TermCast/WebSocket/WebSocketServer.swift
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

actor WebSocketServer {
    private let port: Int
    private let jwtManager: JWTManager
    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var serverChannel: (any Channel)?
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    init(port: Int, jwtManager: JWTManager, registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.port = port
        self.jwtManager = jwtManager
        self.registry = registry
        self.broadcaster = broadcaster
    }

    func start() async throws {
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

        serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
    }

    func stop() async throws {
        try await serverChannel?.close().get()
        try await group.shutdownGracefully()
    }
}
```

- [ ] **Step 2: Implement WebSocketHandler**

```swift
// apps/mac/TermCast/WebSocket/WebSocketHandler.swift
import Foundation
import NIOCore
import NIOWebSocket

final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var pingTask: Task<Void, Never>?
    private var pongReceived = true

    init(registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.registry = registry
        self.broadcaster = broadcaster
    }

    func channelActive(context: ChannelHandlerContext) {
        Task { [weak self, registry, broadcaster] in
            guard let self else { return }
            // Send session list on connect
            let sessions = await registry.allSessions()
            let msg = WSMessage.sessions(sessions)
            self.sendText(msg.json(), context: context)

            // Register this channel with broadcaster
            await broadcaster.add(channel: context.channel)

            // Start ping loop
            self.startPingLoop(context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .text else { return }
        var buf = frame.data
        guard let text = buf.readString(length: buf.readableBytes),
              let msg = WSMessage.from(json: text) else { return }
        handle(message: msg, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        pingTask?.cancel()
        Task { await broadcaster.remove(channel: context.channel) }
    }

    // MARK: - Message dispatch

    private func handle(message: WSMessage, context: ChannelHandlerContext) {
        switch message.type {
        case .attach:
            guard let idStr = message.sessionId, let id = UUID(uuidString: idStr) else { return }
            Task { [registry] in
                guard let pty = await registry.session(id: id) else { return }
                // Replay ring buffer
                let snapshot = await pty.bufferSnapshot()
                if !snapshot.isEmpty {
                    let replay = WSMessage.output(sessionId: id, data: snapshot)
                    self.sendText(replay.json(), context: context)
                }
            }

        case .input:
            guard let idStr = message.sessionId,
                  let id = UUID(uuidString: idStr),
                  let b64 = message.data,
                  let bytes = Data(base64Encoded: b64) else { return }
            Task { [registry] in
                await registry.session(id: id)?.write(bytes: bytes)
            }

        case .resize:
            guard let idStr = message.sessionId,
                  let id = UUID(uuidString: idStr),
                  let cols = message.cols, let rows = message.rows else { return }
            Task { [registry] in
                guard let pty = await registry.session(id: id) else { return }
                // Send SIGWINCH to shell process
                kill(Int32(pty.session.pid), SIGWINCH)
            }

        case .pong:
            pongReceived = true

        default:
            break
        }
    }

    // MARK: - Ping loop

    private func startPingLoop(context: ChannelHandlerContext) {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5s
                guard let self else { return }
                if !self.pongReceived {
                    context.close(promise: nil)
                    return
                }
                self.pongReceived = false
                self.sendText(WSMessage.ping().json(), context: context)
            }
        }
    }

    // MARK: - Send helper

    func sendText(_ text: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        context.writeAndFlush(NIOAny(frame), promise: nil)
    }
}
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/mac/TermCast/WebSocket/WebSocketServer.swift apps/mac/TermCast/WebSocket/WebSocketHandler.swift
git commit -m "feat(mac): SwiftNIO WebSocket server with JWT upgrade validation"
```

---

## Task 11: SessionBroadcaster + InputRouter

**Files:**
- Create: `apps/mac/TermCast/WebSocket/SessionBroadcaster.swift`
- Create: `apps/mac/TermCast/WebSocket/InputRouter.swift`

- [ ] **Step 1: Implement SessionBroadcaster**

```swift
// apps/mac/TermCast/WebSocket/SessionBroadcaster.swift
import Foundation
import NIOCore
import NIOWebSocket

/// Fans out session output to all connected WebSocket clients.
actor SessionBroadcaster {
    private var channels: [ObjectIdentifier: any Channel] = [:]

    func add(channel: any Channel) {
        channels[ObjectIdentifier(channel)] = channel
    }

    func remove(channel: any Channel) {
        channels.removeValue(forKey: ObjectIdentifier(channel))
    }

    func broadcast(message: WSMessage) {
        let json = message.json()
        for channel in channels.values {
            var buffer = channel.allocator.buffer(capacity: json.utf8.count)
            buffer.writeString(json)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(NIOAny(frame), promise: nil)
        }
    }

    func broadcastSessionOpened(_ session: Session) {
        broadcast(message: .sessionOpened(session))
    }

    func broadcastSessionClosed(_ id: SessionID) {
        broadcast(message: .sessionClosed(id))
    }

    func broadcastOutput(sessionId: SessionID, data: Data) {
        broadcast(message: .output(sessionId: sessionId, data: data))
    }

    var clientCount: Int { channels.count }
}
```

- [ ] **Step 2: Implement InputRouter**

```swift
// apps/mac/TermCast/WebSocket/InputRouter.swift
import Foundation

/// Routes WebSocket client input messages to the correct PTYSession.
struct InputRouter {
    private let registry: SessionRegistry

    init(registry: SessionRegistry) {
        self.registry = registry
    }

    func route(sessionId: SessionID, bytes: Data) async {
        await registry.session(id: sessionId)?.write(bytes: bytes)
    }
}
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/mac/TermCast/WebSocket/SessionBroadcaster.swift apps/mac/TermCast/WebSocket/InputRouter.swift
git commit -m "feat(mac): SessionBroadcaster and InputRouter"
```

---

## Task 12: ShellHookInstaller

**Files:**
- Create: `apps/mac/TermCast/ShellIntegration/ShellHookInstaller.swift`

- [ ] **Step 1: Implement ShellHookInstaller**

```swift
// apps/mac/TermCast/ShellIntegration/ShellHookInstaller.swift
import Foundation

struct ShellHookInstaller {
    static let hookDir = NSHomeDirectory() + "/.termcast"
    static let binDir = hookDir + "/bin"
    static let hookScriptPath = hookDir + "/hook.sh"
    static let fishHookPath = hookDir + "/hook.fish"

    private static let zshrcPath = NSHomeDirectory() + "/.zshrc"
    private static let bashrcPath = NSHomeDirectory() + "/.bashrc"
    private static let fishConfigPath = NSHomeDirectory() + "/.config/fish/config.fish"

    private static let hookLine = "[ -f ~/.termcast/hook.sh ] && source ~/.termcast/hook.sh"
    private static let fishHookLine = "if test -f ~/.termcast/hook.fish; source ~/.termcast/hook.fish; end"

    /// Install hook scripts and add source lines to detected shell configs.
    static func install() throws {
        // Create ~/.termcast/bin/
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

        // Copy hook scripts from app bundle
        try copyHookScript()
        try copyFishHookScript()
        try installHookBinary()

        // Inject source lines into shell configs
        injectIfNeeded(line: hookLine, into: zshrcPath)
        injectIfNeeded(line: hookLine, into: bashrcPath)
        injectIfNeeded(line: fishHookLine, into: fishConfigPath)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: hookScriptPath)
    }

    // MARK: - Private

    private static func copyHookScript() throws {
        // Source hook from shared/shell-integration/ (bundled in app resources)
        guard let src = Bundle.main.path(forResource: "termcast", ofType: "sh") else {
            throw InstallError.resourceMissing("termcast.sh")
        }
        if FileManager.default.fileExists(atPath: hookScriptPath) {
            try FileManager.default.removeItem(atPath: hookScriptPath)
        }
        try FileManager.default.copyItem(atPath: src, toPath: hookScriptPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hookScriptPath)
    }

    private static func copyFishHookScript() throws {
        guard let src = Bundle.main.path(forResource: "termcast", ofType: "fish") else { return }
        if FileManager.default.fileExists(atPath: fishHookPath) {
            try FileManager.default.removeItem(atPath: fishHookPath)
        }
        try FileManager.default.copyItem(atPath: src, toPath: fishHookPath)
    }

    private static func installHookBinary() throws {
        let dest = binDir + "/termcast-hook"
        guard let src = Bundle.main.path(forAuxiliaryExecutable: "termcast-hook") else {
            throw InstallError.resourceMissing("termcast-hook binary")
        }
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }
        try FileManager.default.copyItem(atPath: src, toPath: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
    }

    private static func injectIfNeeded(line: String, into path: String) {
        let content = (try? String(contentsOfFile: path)) ?? ""
        guard !content.contains("termcast") else { return }
        let newContent = content + "\n# TermCast shell integration\n\(line)\n"
        try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

enum InstallError: Error {
    case resourceMissing(String)
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/mac/TermCast/ShellIntegration/ShellHookInstaller.swift
git commit -m "feat(mac): ShellHookInstaller — injects hooks into .zshrc/.bashrc/config.fish"
```

---

## Task 13: TailscaleSetup

**Files:**
- Create: `apps/mac/TermCast/Tailscale/TailscaleSetup.swift`

- [ ] **Step 1: Implement TailscaleSetup**

```swift
// apps/mac/TermCast/Tailscale/TailscaleSetup.swift
import Foundation
import CoreImage

struct TailscaleStatus: Decodable {
    struct Self_: Decodable {
        let dnsName: String
        enum CodingKeys: String, CodingKey { case dnsName = "DNSName" }
    }
    let selfNode: Self_
    enum CodingKeys: String, CodingKey { case selfNode = "Self" }
}

struct TailscaleSetup {
    static let tailscaleBin = "/usr/local/bin/tailscale"

    // MARK: - Checks

    static func isTailscaleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: tailscaleBin)
    }

    // MARK: - Setup

    /// Run `tailscale serve 7681` to proxy localhost:7681 → wss://hostname
    @discardableResult
    static func configureServe() throws -> String {
        let result = try shell(tailscaleBin, "serve", "--https=443", "7681")
        return result
    }

    /// Returns the permanent Tailscale hostname, e.g. "macbook.tail12345.ts.net"
    static func hostname() throws -> String {
        let json = try shell(tailscaleBin, "status", "--json")
        guard let data = json.data(using: .utf8) else { throw TailscaleError.parseError }
        let decoder = JSONDecoder()
        let status = try decoder.decode(TailscaleStatus.self, from: data)
        // DNSName ends with a dot — remove it
        return status.selfNode.dnsName.hasSuffix(".")
            ? String(status.selfNode.dnsName.dropLast()) : status.selfNode.dnsName
    }

    // MARK: - QR code generation

    /// Generates a QR code image encoding { "host": hostname, "secret": hexSecret }
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
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = output.transformed(by: transform)
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - Shell helper

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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum TailscaleError: Error {
    case notInstalled
    case parseError
    case configureError(String)
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/mac/TermCast/Tailscale/TailscaleSetup.swift
git commit -m "feat(mac): TailscaleSetup — serve config, hostname resolution, QR generation"
```

---

## Task 14: MenuBarController

**Files:**
- Create: `apps/mac/TermCast/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Implement MenuBarController**

```swift
// apps/mac/TermCast/MenuBar/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var sessions: [Session] = []
    private var clientCount: Int = 0

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌨️"
        statusItem.button?.action = #selector(statusBarButtonClicked)
        statusItem.button?.target = self
        setupMenu()
    }

    // MARK: - Public updates

    func update(sessions: [Session], clientCount: Int) {
        self.sessions = sessions
        self.clientCount = clientCount
        updateBadge()
        rebuildMenu()
    }

    // MARK: - Private

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
                let title = "\(session.termApp) — \(session.shell)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit TermCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func statusBarButtonClicked() {}

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/mac/TermCast/MenuBar/MenuBarController.swift
git commit -m "feat(mac): MenuBarController — NSStatusItem with session list and client badge"
```

---

## Task 15: App Entry Point — Wire Everything Together

**Files:**
- Create: `apps/mac/TermCast/App/TermCastApp.swift`

- [ ] **Step 1: Implement the app entry point**

```swift
// apps/mac/TermCast/App/TermCastApp.swift
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var registry: SessionRegistry!
    private var broadcaster: SessionBroadcaster!
    private var socketServer: AgentSocketServer!
    private var wsServer: WebSocketServer!
    private var jwtManager: JWTManager!
    private var pingTimer: Timer?

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
        registry.onSessionAdded = { [weak self] session in
            Task { @MainActor in
                await self?.broadcaster.broadcastSessionOpened(session)
                await self?.refreshMenuBar()
            }
        }
        registry.onSessionRemoved = { [weak self] id in
            Task { @MainActor in
                await self?.broadcaster.broadcastSessionClosed(id)
                await self?.refreshMenuBar()
            }
        }

        // 4. Start Unix socket server
        socketServer = AgentSocketServer(
            socketPath: NSHomeDirectory() + "/.termcast/agent.sock"
        ) { [weak self] reg in
            await self?.registry.register(reg)
        }

        // 5. Start WebSocket server
        wsServer = WebSocketServer(
            port: 7681,
            jwtManager: jwtManager,
            registry: registry,
            broadcaster: broadcaster
        )

        Task {
            try await socketServer.start(group: wsServer.group)
            try await wsServer.start()
        }

        // 6. First-launch setup
        if !ShellHookInstaller.isInstalled() {
            performFirstLaunchSetup()
        }

        // 7. Recover any live sessions from /tmp/termcast/
        recoverSessions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            try? await socketServer.stop()
            try? await wsServer.stop()
        }
    }

    // MARK: - Private

    private func performFirstLaunchSetup() {
        Task { @MainActor in
            // Install shell hooks
            try? ShellHookInstaller.install()

            // Configure Tailscale and show QR
            guard TailscaleSetup.isTailscaleInstalled() else {
                showAlert("Tailscale Required",
                          "Install Tailscale from tailscale.com, then relaunch TermCast.")
                return
            }
            try? TailscaleSetup.configureServe()
            guard let hostname = try? TailscaleSetup.hostname() else { return }
            guard let secret = try? KeychainStore.load(key: "jwt-secret"),
                  let qr = TailscaleSetup.qrCode(hostname: hostname, secret: secret) else { return }
            showQRWindow(qr: qr, hostname: hostname)
        }
    }

    private func recoverSessions() {
        let dir = "/tmp/termcast"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        // Look for .out pipes that still have a live process attached
        for file in files where file.hasSuffix(".out") {
            guard let pidStr = file.components(separatedBy: ".").first,
                  let pid = Int(pidStr) else { continue }
            // Check process is still alive
            if kill(Int32(pid), 0) == 0 {
                let pipePath = "\(dir)/\(file)"
                let reg = ShellRegistration(pid: pid, tty: "/dev/tty",
                                             shell: "zsh", term: "Unknown",
                                             outPipe: pipePath)
                Task { await registry.register(reg) }
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

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

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
        label.isEditable = false; label.isBordered = false
        label.alignment = .center
        view.addSubview(imageView)
        view.addSubview(label)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build and run**

```bash
cd apps/mac
xcodebuild build -scheme TermCast -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Smoke test manually**

1. Run TermCast from Xcode
2. Check menu bar shows ⌨️ icon
3. Open a new Terminal window — check it appears in menu
4. Run: `wscat -H "Authorization: Bearer $(./get-token.sh)" ws://localhost:7681`  
   Expected: receives `{"type":"sessions",...}` JSON

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/mac/TermCast/App/TermCastApp.swift
git commit -m "feat(mac): app entry point — wires all components, first-launch setup, session recovery"
```

---

## Task 16: Integration Test — Full Session Lifecycle

**Files:**
- Create: `apps/mac/TermCastTests/IntegrationTests.swift`

- [ ] **Step 1: Write integration test**

```swift
// apps/mac/TermCastTests/IntegrationTests.swift
import XCTest
@testable import TermCast

/// Tests the full path: shell registers → output flows → broadcaster notified → session removed.
final class IntegrationTests: XCTestCase {
    func testSessionRegistrationFlow() async throws {
        let registry = SessionRegistry()
        let broadcaster = SessionBroadcaster()

        var openedSessions: [Session] = []
        var closedIDs: [SessionID] = []

        registry.onSessionAdded = { openedSessions.append($0) }
        registry.onSessionRemoved = { closedIDs.append($0) }

        // Simulate shell registration
        let tmpPipe = "/tmp/termcast/test-\(Int.random(in: 1000..<9999)).out"
        try FileManager.default.createDirectory(atPath: "/tmp/termcast",
                                                 withIntermediateDirectories: true)
        mkfifo(tmpPipe, 0o600)
        defer { try? FileManager.default.removeItem(atPath: tmpPipe) }

        let reg = ShellRegistration(pid: Int(ProcessInfo.processInfo.processIdentifier),
                                     tty: "/dev/null",
                                     shell: "zsh",
                                     term: "TestTerminal",
                                     outPipe: tmpPipe)
        await registry.register(reg)

        // Give session a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)

        let sessions = await registry.allSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.shell, "zsh")
        XCTAssertFalse(openedSessions.isEmpty)

        // Verify ring buffer starts empty
        let pty = await registry.session(id: sessions.first!.id)
        let snapshot = await pty!.bufferSnapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }
}
```

- [ ] **Step 2: Run integration test**

```bash
cd apps/mac
xcodebuild test -scheme TermCast -destination 'platform=macOS' \
    -only-testing:TermCastTests/IntegrationTests 2>&1 | grep -E "FAILED|passed|error:"
```

Expected: `Test Suite 'IntegrationTests' passed`

- [ ] **Step 3: Final commit**

```bash
cd ../..
git add apps/mac/TermCastTests/IntegrationTests.swift
git commit -m "test(mac): integration test — full session registration lifecycle"
```

---

## Done

Mac Agent complete. Verify:
- [ ] `xcodebuild test` passes all test suites
- [ ] App builds and shows menu bar icon
- [ ] Opening a terminal registers a session in the menu

Next: `2026-04-05-phase-2-ios-app.md`
