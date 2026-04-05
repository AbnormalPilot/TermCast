# Phase 2: iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native iOS app that scans a QR code to pair with the Mac, connects via WebSocket over Tailscale, and renders live interactive terminal sessions using SwiftTerm.

**Architecture:** SwiftUI app with `@Observable` state. `Network.framework` WebSocket client with exponential backoff reconnect. SwiftTerm for native terminal rendering (no WebView). Credentials in Keychain. Keyboard toolbar pinned above system keyboard via `inputAccessoryView`.

**Tech Stack:** Swift 5.10, iOS 16+, SwiftUI, SwiftTerm (SPM), Network.framework, AVFoundation (QR scan), Security.framework (Keychain)

---

## File Map

```
apps/ios/
├── TermCastiOS.xcodeproj
├── TermCastiOS/
│   ├── App/
│   │   ├── TermCastiOSApp.swift          # @main, root navigation
│   │   └── Info.plist                    # NSCameraUsageDescription
│   ├── Models/
│   │   ├── Session.swift                 # Mirror of Mac Session (Codable)
│   │   └── WSMessage.swift               # Mirror of Mac WSMessage (Codable)
│   ├── Auth/
│   │   └── PairingStore.swift            # Keychain: host + JWT secret
│   ├── Connection/
│   │   ├── WSClient.swift                # Network.framework WebSocket client
│   │   ├── ReconnectPolicy.swift         # Exponential backoff: 1s→60s
│   │   └── PingPong.swift                # 5s keepalive
│   ├── Sessions/
│   │   └── SessionStore.swift            # @Observable: [SessionID: SessionState]
│   ├── Onboarding/
│   │   └── QRScanView.swift              # AVFoundation camera QR decoder
│   ├── Terminal/
│   │   ├── TerminalView.swift            # SwiftTerm TerminalView in SwiftUI
│   │   ├── InputHandler.swift            # Keystroke → ANSI sequence → WSClient
│   │   └── KeyboardToolbar.swift         # Ctrl/Esc/Tab/arrows above keyboard
│   ├── Views/
│   │   ├── SessionListView.swift         # Tab bar of available sessions
│   │   ├── SessionTabView.swift          # One tab: TerminalView + toolbar
│   │   └── OfflineView.swift             # "Mac offline" full-screen state
└── TermCastiOSTests/
    ├── ReconnectPolicyTests.swift
    ├── InputHandlerTests.swift
    └── PairingStoreTests.swift
```

---

## Task 1: Xcode Project + SwiftTerm Dependency

**Files:**
- Create: `apps/ios/TermCastiOS.xcodeproj`
- Create: `apps/ios/TermCastiOS/App/Info.plist`

- [ ] **Step 1: Create Xcode project**

In Xcode: File → New Project → iOS → App  
- Product Name: `TermCastiOS`  
- Bundle ID: `com.termcast.ios`  
- Interface: SwiftUI  
- Language: Swift  
- Minimum Deployment: iOS 16.0  
- Save to: `apps/ios/`

- [ ] **Step 2: Add SwiftTerm via SPM**

Xcode → File → Add Package Dependencies  
URL: `https://github.com/migueldeicaza/SwiftTerm`  
Version: Up to Next Major from `1.2.0`  
Add to target: `TermCastiOS`

- [ ] **Step 3: Update Info.plist**

```xml
<!-- apps/ios/TermCastiOS/App/Info.plist — add these keys -->
<key>NSCameraUsageDescription</key>
<string>TermCast uses the camera to scan the QR code shown on your Mac.</string>
```

- [ ] **Step 4: Verify build**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/ios/
git commit -m "feat(ios): xcode project scaffold with SwiftTerm dependency"
```

---

## Task 2: Models — Session + WSMessage

**Files:**
- Create: `apps/ios/TermCastiOS/Models/Session.swift`
- Create: `apps/ios/TermCastiOS/Models/WSMessage.swift`

These mirror the Mac models exactly so JSON from the server deserialises correctly.

- [ ] **Step 1: Write failing tests**

```swift
// apps/ios/TermCastiOSTests/ModelsTests.swift
import XCTest
@testable import TermCastiOS

final class ModelsTests: XCTestCase {
    func testSessionDecoding() throws {
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440000","pid":123,"tty":"/dev/ttys003",
         "shell":"zsh","termApp":"iTerm2","outPipe":"/tmp/test.out",
         "isActive":true,"cols":80,"rows":24}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(session.shell, "zsh")
        XCTAssertEqual(session.cols, 80)
    }

    func testWSMessagePingDecoding() throws {
        let json = """{"type":"ping"}"""
        let msg = WSMessage.from(json: json)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.type, .ping)
    }

    func testWSMessageOutputHasBase64() throws {
        let json = """{"type":"output","session_id":"abc","data":"aGVsbG8="}"""
        let msg = try XCTUnwrap(WSMessage.from(json: json))
        XCTAssertEqual(msg.data, "aGVsbG8=")
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

Expected: `error: cannot find type 'Session'`

- [ ] **Step 3: Implement Session.swift**

```swift
// apps/ios/TermCastiOS/Models/Session.swift
import Foundation

typealias SessionID = UUID

struct Session: Codable, Identifiable, Sendable, Hashable {
    let id: SessionID
    let pid: Int
    let tty: String
    let shell: String
    let termApp: String
    let outPipe: String
    var isActive: Bool
    var cols: Int
    var rows: Int
}
```

- [ ] **Step 4: Implement WSMessage.swift**

```swift
// apps/ios/TermCastiOS/Models/WSMessage.swift
import Foundation

enum WSMessageType: String, Codable {
    case sessions, sessionOpened, sessionClosed, output, resize, ping
    case attach, input, pong
}

struct WSMessage: Codable {
    let type: WSMessageType
    var sessions: [Session]?
    var session: Session?
    var sessionId: String?
    var data: String?
    var cols: Int?
    var rows: Int?

    static func attach(sessionId: SessionID) -> WSMessage {
        WSMessage(type: .attach, sessionId: sessionId.uuidString)
    }
    static func input(sessionId: SessionID, bytes: Data) -> WSMessage {
        WSMessage(type: .input, sessionId: sessionId.uuidString,
                  data: bytes.base64EncodedString())
    }
    static func resize(sessionId: SessionID, cols: Int, rows: Int) -> WSMessage {
        WSMessage(type: .resize, sessionId: sessionId.uuidString, cols: cols, rows: rows)
    }
    static func pong() -> WSMessage { WSMessage(type: .pong) }

    static func from(json: String) -> WSMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(WSMessage.self, from: data)
    }

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 6: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Models/ apps/ios/TermCastiOSTests/ModelsTests.swift
git commit -m "feat(ios): Session and WSMessage models"
```

---

## Task 3: PairingStore (Keychain)

**Files:**
- Create: `apps/ios/TermCastiOS/Auth/PairingStore.swift`
- Create: `apps/ios/TermCastiOSTests/PairingStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/ios/TermCastiOSTests/PairingStoreTests.swift
import XCTest
@testable import TermCastiOS

final class PairingStoreTests: XCTestCase {
    override func setUp() { PairingStore.clear() }
    override func tearDown() { PairingStore.clear() }

    func testSaveAndLoad() throws {
        try PairingStore.save(host: "macbook.ts.net", secret: Data([0xAB, 0xCD]))
        let creds = try PairingStore.load()
        XCTAssertEqual(creds.host, "macbook.ts.net")
        XCTAssertEqual(creds.secret, Data([0xAB, 0xCD]))
    }

    func testLoadThrowsWhenEmpty() {
        XCTAssertThrowsError(try PairingStore.load())
    }

    func testClearRemovesCredentials() throws {
        try PairingStore.save(host: "host", secret: Data([1, 2]))
        PairingStore.clear()
        XCTAssertThrowsError(try PairingStore.load())
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'PairingStore'`

- [ ] **Step 3: Implement PairingStore**

```swift
// apps/ios/TermCastiOS/Auth/PairingStore.swift
import Foundation
import Security

struct PairingCredentials {
    let host: String
    let secret: Data
}

enum PairingStore {
    private static let service = "com.termcast.ios"
    private static let hostKey = "termcast-host"
    private static let secretKey = "termcast-secret"

    static func save(host: String, secret: Data) throws {
        try keychainSave(key: hostKey, data: Data(host.utf8))
        try keychainSave(key: secretKey, data: secret)
    }

    static func load() throws -> PairingCredentials {
        let hostData = try keychainLoad(key: hostKey)
        let secret = try keychainLoad(key: secretKey)
        guard let host = String(data: hostData, encoding: .utf8) else {
            throw PairingError.invalidData
        }
        return PairingCredentials(host: host, secret: secret)
    }

    static func clear() {
        keychainDelete(key: hostKey)
        keychainDelete(key: secretKey)
    }

    // MARK: - Keychain helpers

    private static func keychainSave(key: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PairingError.keychainError(status) }
    }

    private static func keychainLoad(key: String) throws -> Data {
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
            throw PairingError.notFound
        }
        return data
    }

    private static func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum PairingError: Error {
    case notFound
    case invalidData
    case keychainError(OSStatus)
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:TermCastiOSTests/PairingStoreTests 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Auth/PairingStore.swift apps/ios/TermCastiOSTests/PairingStoreTests.swift
git commit -m "feat(ios): PairingStore — host + secret in Keychain"
```

---

## Task 4: ReconnectPolicy + Tests

**Files:**
- Create: `apps/ios/TermCastiOS/Connection/ReconnectPolicy.swift`
- Create: `apps/ios/TermCastiOSTests/ReconnectPolicyTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/ios/TermCastiOSTests/ReconnectPolicyTests.swift
import XCTest
@testable import TermCastiOS

final class ReconnectPolicyTests: XCTestCase {
    func testFirstAttemptIsOneSecond() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.nextDelay(), 1.0, accuracy: 0.01)
    }

    func testDoublesEachAttempt() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.nextDelay(), 1.0, accuracy: 0.01)
        XCTAssertEqual(policy.nextDelay(), 2.0, accuracy: 0.01)
        XCTAssertEqual(policy.nextDelay(), 4.0, accuracy: 0.01)
        XCTAssertEqual(policy.nextDelay(), 8.0, accuracy: 0.01)
    }

    func testCapsAt60Seconds() {
        let policy = ReconnectPolicy()
        var last = 0.0
        for _ in 0..<20 { last = policy.nextDelay() }
        XCTAssertLessThanOrEqual(last, 60.0)
    }

    func testResetRestartsBacking() {
        let policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), 1.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'ReconnectPolicy'`

- [ ] **Step 3: Implement ReconnectPolicy**

```swift
// apps/ios/TermCastiOS/Connection/ReconnectPolicy.swift
import Foundation

final class ReconnectPolicy {
    private var attempt: Int = 0
    private let base: Double = 1.0
    private let cap: Double = 60.0

    func nextDelay() -> TimeInterval {
        let delay = min(base * pow(2.0, Double(attempt)), cap)
        attempt += 1
        return delay
    }

    func reset() {
        attempt = 0
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:TermCastiOSTests/ReconnectPolicyTests 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Connection/ReconnectPolicy.swift apps/ios/TermCastiOSTests/ReconnectPolicyTests.swift
git commit -m "feat(ios): ReconnectPolicy — exponential backoff 1s→60s"
```

---

## Task 5: WSClient + PingPong

**Files:**
- Create: `apps/ios/TermCastiOS/Connection/WSClient.swift`
- Create: `apps/ios/TermCastiOS/Connection/PingPong.swift`

- [ ] **Step 1: Implement WSClient**

```swift
// apps/ios/TermCastiOS/Connection/WSClient.swift
import Foundation
import Network

enum WSClientState {
    case disconnected, connecting, connected, offline
}

@Observable
final class WSClient {
    private(set) var state: WSClientState = .disconnected
    var onMessage: ((WSMessage) -> Void)?
    var onStateChange: ((WSClientState) -> Void)?

    private var connection: NWConnection?
    private let policy = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var pingPong: PingPong?

    // MARK: - Connect

    func connect(host: String, secret: Data) {
        let token = buildJWT(secret: secret)
        let endpoint = NWEndpoint.url(URL(string: "wss://\(host)")!)
        let params = NWParameters.tls
        params.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolWebSocket.Options(), at: 0
        )
        // Add Authorization header
        if let wsOpts = params.defaultProtocolStack.applicationProtocols.first as? NWProtocolWebSocket.Options {
            wsOpts.setAdditionalHeaders([("Authorization", "Bearer \(token)")])
        }

        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn
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
    }

    func send(_ message: WSMessage) {
        guard let conn = connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        guard let data = message.json().data(using: .utf8) else { return }
        conn.send(content: data, contentContext: context, completion: .idempotent)
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWConnection.State, host: String, secret: Data) {
        switch state {
        case .ready:
            setState(.connected)
            policy.reset()
            pingPong = PingPong(
                onSendPing: { [weak self] in
                    self?.send(.pong())  // send pong as keepalive
                },
                onTimeout: { [weak self] in
                    self?.scheduleReconnect(host: host, secret: secret)
                }
            )
            pingPong?.start()

        case .failed, .cancelled:
            setState(.offline)
            scheduleReconnect(host: host, secret: secret)

        default: break
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            if let error { return }
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
        // Minimal JWT: header.payload.signature (HS256)
        // In production, use a proper JWT library or mirror Mac's JWTManager
        let header = base64url(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 30 * 24 * 3600
        let payloadStr = #"{"sub":"termcast-client","iat":\#(now),"exp":\#(exp)}"#
        let payload = base64url(Data(payloadStr.utf8))
        let msg = "\(header).\(payload)"
        // HMAC-SHA256 via CommonCrypto
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        msg.withCString { msgPtr in
            secret.withUnsafeBytes { keyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyPtr.baseAddress, secret.count,
                       msgPtr, strlen(msgPtr), &digest)
            }
        }
        let sig = base64url(Data(digest))
        return "\(msg).\(sig)"
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

Note: `CCHmac` requires adding `import CommonCrypto` and linking `Security.framework` (already linked by default on iOS).

- [ ] **Step 2: Implement PingPong**

```swift
// apps/ios/TermCastiOS/Connection/PingPong.swift
import Foundation

final class PingPong {
    private let onSendPing: () -> Void
    private let onTimeout: () -> Void
    private var timer: Timer?
    private var pongReceived = true

    init(onSendPing: @escaping () -> Void, onTimeout: @escaping () -> Void) {
        self.onSendPing = onSendPing
        self.onTimeout = onTimeout
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.pongReceived {
                self.onTimeout()
                return
            }
            self.pongReceived = false
            self.onSendPing()
        }
    }

    func didReceivePong() {
        pongReceived = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Connection/
git commit -m "feat(ios): WSClient (Network.framework) + PingPong keepalive"
```

---

## Task 6: SessionStore

**Files:**
- Create: `apps/ios/TermCastiOS/Sessions/SessionStore.swift`

- [ ] **Step 1: Implement SessionStore**

```swift
// apps/ios/TermCastiOS/Sessions/SessionStore.swift
import Foundation

enum SessionState {
    case active
    case ended   // session closed, history preserved for scroll
}

@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var states: [SessionID: SessionState] = [:]

    // MARK: - Updates from WebSocket messages

    func apply(_ message: WSMessage) {
        switch message.type {
        case .sessions:
            sessions = message.sessions ?? []
            for s in sessions { states[s.id] = .active }

        case .sessionOpened:
            if let session = message.session {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions.append(session)
                }
                states[session.id] = .active
            }

        case .sessionClosed:
            if let idStr = message.sessionId, let id = UUID(uuidString: idStr) {
                states[id] = .ended
                // Don't remove — keep tab open for scroll history
            }

        default: break
        }
    }

    func state(for id: SessionID) -> SessionState {
        states[id] ?? .ended
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Sessions/SessionStore.swift
git commit -m "feat(ios): SessionStore — @Observable session list from WS messages"
```

---

## Task 7: InputHandler + Tests

**Files:**
- Create: `apps/ios/TermCastiOS/Terminal/InputHandler.swift`
- Create: `apps/ios/TermCastiOSTests/InputHandlerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/ios/TermCastiOSTests/InputHandlerTests.swift
import XCTest
@testable import TermCastiOS

final class InputHandlerTests: XCTestCase {
    func testPlainTextPassthrough() {
        let bytes = InputHandler.encode(text: "hello")
        XCTAssertEqual(bytes, Data("hello".utf8))
    }

    func testCtrlC() {
        // Ctrl+C = ETX = 0x03
        let bytes = InputHandler.encode(ctrl: "c")
        XCTAssertEqual(bytes, Data([0x03]))
    }

    func testCtrlA() {
        let bytes = InputHandler.encode(ctrl: "a")
        XCTAssertEqual(bytes, Data([0x01]))
    }

    func testEscape() {
        let bytes = InputHandler.encode(special: .escape)
        XCTAssertEqual(bytes, Data([0x1b]))
    }

    func testTab() {
        let bytes = InputHandler.encode(special: .tab)
        XCTAssertEqual(bytes, Data([0x09]))
    }

    func testArrowUp() {
        let bytes = InputHandler.encode(special: .arrowUp)
        XCTAssertEqual(bytes, Data([0x1b, 0x5b, 0x41]))  // ESC[A
    }

    func testArrowDown() {
        let bytes = InputHandler.encode(special: .arrowDown)
        XCTAssertEqual(bytes, Data([0x1b, 0x5b, 0x42]))  // ESC[B
    }

    func testArrowRight() {
        let bytes = InputHandler.encode(special: .arrowRight)
        XCTAssertEqual(bytes, Data([0x1b, 0x5b, 0x43]))  // ESC[C
    }

    func testArrowLeft() {
        let bytes = InputHandler.encode(special: .arrowLeft)
        XCTAssertEqual(bytes, Data([0x1b, 0x5b, 0x44]))  // ESC[D
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Expected: `error: cannot find type 'InputHandler'`

- [ ] **Step 3: Implement InputHandler**

```swift
// apps/ios/TermCastiOS/Terminal/InputHandler.swift
import Foundation

enum SpecialKey {
    case escape, tab, arrowUp, arrowDown, arrowLeft, arrowRight
}

enum InputHandler {
    /// Encode plain text input
    static func encode(text: String) -> Data {
        Data(text.utf8)
    }

    /// Encode Ctrl+letter (a–z) → control character (0x01–0x1a)
    static func encode(ctrl letter: Character) -> Data {
        let lower = letter.lowercased().first ?? letter
        guard let ascii = lower.asciiValue, ascii >= 97 && ascii <= 122 else { return Data() }
        return Data([ascii - 96])  // 'a'=0x61 → 0x01, 'c'=0x63 → 0x03
    }

    /// Encode special keys as ANSI escape sequences
    static func encode(special key: SpecialKey) -> Data {
        switch key {
        case .escape:     return Data([0x1b])
        case .tab:        return Data([0x09])
        case .arrowUp:    return Data([0x1b, 0x5b, 0x41])  // ESC[A
        case .arrowDown:  return Data([0x1b, 0x5b, 0x42])  // ESC[B
        case .arrowRight: return Data([0x1b, 0x5b, 0x43])  // ESC[C
        case .arrowLeft:  return Data([0x1b, 0x5b, 0x44])  // ESC[D
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd apps/ios
xcodebuild test -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:TermCastiOSTests/InputHandlerTests 2>&1 | grep -E "FAILED|passed"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Terminal/InputHandler.swift apps/ios/TermCastiOSTests/InputHandlerTests.swift
git commit -m "feat(ios): InputHandler — text/ctrl/special key → ANSI byte sequences"
```

---

## Task 8: QRScanView

**Files:**
- Create: `apps/ios/TermCastiOS/Onboarding/QRScanView.swift`

- [ ] **Step 1: Implement QRScanView**

```swift
// apps/ios/TermCastiOS/Onboarding/QRScanView.swift
import SwiftUI
import AVFoundation

struct PairingPayload: Decodable {
    let host: String
    let secret: String   // hex-encoded
}

struct QRScanView: View {
    let onPaired: (String, Data) -> Void

    var body: some View {
        ZStack {
            CameraPreview(onCode: { code in
                guard let data = code.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(PairingPayload.self, from: data),
                      let secret = Data(hexEncoded: payload.secret) else { return }
                onPaired(payload.host, secret)
            })
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text("Scan the QR code shown on your Mac")
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Camera preview using AVFoundation

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.onCode = onCode
        return view
    }

    func updateUIView(_ uiView: CameraView, context: Context) {}
}

private final class CameraView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        if session == nil { setupCamera() }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.previewLayer = layer
        self.session = session

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        session?.stopRunning()
        onCode?(value)
    }
}

// MARK: - Data hex decoding

extension Data {
    init?(hexEncoded hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var idx = chars.startIndex
        while idx < chars.endIndex {
            let nextIdx = chars.index(idx, offsetBy: 2)
            guard let byte = UInt8(String(chars[idx..<nextIdx]), radix: 16) else { return nil }
            bytes.append(byte)
            idx = nextIdx
        }
        self.init(bytes)
    }
}
```

- [ ] **Step 2: Build — expect no errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Onboarding/QRScanView.swift
git commit -m "feat(ios): QRScanView — AVFoundation camera QR decoder + pairing payload"
```

---

## Task 9: TerminalView + KeyboardToolbar

**Files:**
- Create: `apps/ios/TermCastiOS/Terminal/TerminalView.swift`
- Create: `apps/ios/TermCastiOS/Terminal/KeyboardToolbar.swift`

- [ ] **Step 1: Implement TerminalView wrapping SwiftTerm**

```swift
// apps/ios/TermCastiOS/Terminal/TerminalView.swift
import SwiftUI
import SwiftTerm

struct TerminalView: UIViewRepresentable {
    let sessionId: SessionID
    @Binding var pendingOutput: Data?
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeUIView(context: Context) -> LocalProcessTerminalView {
        let termView = LocalProcessTerminalView(frame: .zero)
        termView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        context.coordinator.termView = termView
        termView.inputAccessoryView = context.coordinator.toolbar
        return termView
    }

    func updateUIView(_ uiView: LocalProcessTerminalView, context: Context) {
        if let data = pendingOutput {
            // Feed bytes to terminal emulator
            data.withUnsafeBytes { ptr in
                let bytes = Array(ptr.bindMemory(to: UInt8.self))
                uiView.feed(byteArray: ArraySlice(bytes))
            }
            // Clear pending after feeding
            DispatchQueue.main.async { self.pendingOutput = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    final class Coordinator: NSObject {
        let onInput: (Data) -> Void
        let onResize: (Int, Int) -> Void
        weak var termView: LocalProcessTerminalView?
        lazy var toolbar = KeyboardToolbarView(coordinator: self)

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func send(_ bytes: Data) {
            onInput(bytes)
        }
    }
}
```

- [ ] **Step 2: Implement KeyboardToolbar**

```swift
// apps/ios/TermCastiOS/Terminal/KeyboardToolbar.swift
import UIKit
import SwiftUI

final class KeyboardToolbarView: UIView {
    private weak var coordinator: TerminalView.Coordinator?
    private var ctrlPending = false

    init(coordinator: TerminalView.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        backgroundColor = UIColor.systemGray6
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let buttons: [(String, Selector)] = [
            ("Ctrl", #selector(ctrl)),
            ("Esc",  #selector(esc)),
            ("Tab",  #selector(tab)),
            ("↑",    #selector(arrowUp)),
            ("↓",    #selector(arrowDown)),
            ("←",    #selector(arrowLeft)),
            ("→",    #selector(arrowRight)),
        ]

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        for (title, action) in buttons {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            btn.backgroundColor = .systemBackground
            btn.layer.cornerRadius = 6
            btn.addTarget(self, action: action, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    @objc private func ctrl() {
        ctrlPending = true
        // Visual feedback: highlight button
        // Next key press will be sent as Ctrl+key
        // (handled by coordinating with the terminal's key input delegate)
    }

    @objc private func esc()        { send(InputHandler.encode(special: .escape)) }
    @objc private func tab()        { send(InputHandler.encode(special: .tab)) }
    @objc private func arrowUp()    { send(InputHandler.encode(special: .arrowUp)) }
    @objc private func arrowDown()  { send(InputHandler.encode(special: .arrowDown)) }
    @objc private func arrowLeft()  { send(InputHandler.encode(special: .arrowLeft)) }
    @objc private func arrowRight() { send(InputHandler.encode(special: .arrowRight)) }

    private func send(_ data: Data) { coordinator?.send(data) }

    /// Called by key input: if Ctrl is pending, encode as control char
    func handleKey(_ char: Character) -> Bool {
        guard ctrlPending else { return false }
        ctrlPending = false
        send(InputHandler.encode(ctrl: char))
        return true
    }
}
```

- [ ] **Step 3: Build — expect no errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Terminal/
git commit -m "feat(ios): TerminalView (SwiftTerm) + KeyboardToolbar with Ctrl/Esc/Tab/arrows"
```

---

## Task 10: Views — SessionList, SessionTab, OfflineView

**Files:**
- Create: `apps/ios/TermCastiOS/Views/SessionListView.swift`
- Create: `apps/ios/TermCastiOS/Views/SessionTabView.swift`
- Create: `apps/ios/TermCastiOS/Views/OfflineView.swift`

- [ ] **Step 1: Implement OfflineView**

```swift
// apps/ios/TermCastiOS/Views/OfflineView.swift
import SwiftUI

struct OfflineView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Mac Offline")
                .font(.title2.bold())
            Text("TermCast can't reach your Mac.\nMake sure it's running and connected to Tailscale.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 2: Implement SessionTabView**

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

- [ ] **Step 3: Implement SessionListView**

```swift
// apps/ios/TermCastiOS/Views/SessionListView.swift
import SwiftUI

struct SessionListView: View {
    @State var sessionStore: SessionStore
    let wsClient: WSClient

    var body: some View {
        if sessionStore.sessions.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Active Sessions")
                    .font(.title3.bold())
                Text("Open a terminal on your Mac and\nit will appear here automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else {
            TabView {
                ForEach(sessionStore.sessions) { session in
                    SessionTabView(session: session, wsClient: wsClient)
                        .tabItem {
                            Label(session.shell, systemImage: "terminal")
                        }
                        .tag(session.id)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build — expect no errors**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/Views/
git commit -m "feat(ios): SessionListView, SessionTabView, OfflineView"
```

---

## Task 11: App Entry Point — Navigation + Message Dispatch

**Files:**
- Create: `apps/ios/TermCastiOS/App/TermCastiOSApp.swift`

- [ ] **Step 1: Implement app entry point**

```swift
// apps/ios/TermCastiOS/App/TermCastiOSApp.swift
import SwiftUI

@main
struct TermCastiOSApp: App {
    @State private var wsClient = WSClient()
    @State private var sessionStore = SessionStore()
    @State private var isOnboarding = !PairingStore.hasCredentials()
    @State private var isOffline = false

    var body: some Scene {
        WindowGroup {
            if isOnboarding {
                QRScanView { host, secret in
                    try? PairingStore.save(host: host, secret: secret)
                    isOnboarding = false
                    connect()
                }
            } else if isOffline {
                OfflineView {
                    isOffline = false
                    connect()
                }
            } else {
                SessionListView(sessionStore: sessionStore, wsClient: wsClient)
            }
        }
        .onChange(of: wsClient.state) { _, newState in
            switch newState {
            case .offline: isOffline = true
            case .connected: isOffline = false
            default: break
            }
        }
        .task { connect() }
    }

    private func connect() {
        guard let creds = try? PairingStore.load() else {
            isOnboarding = true
            return
        }
        wsClient.onMessage = { [weak sessionStore] msg in
            guard let sessionStore else { return }
            sessionStore.apply(msg)
            dispatchToTerminals(msg)
        }
        wsClient.connect(host: creds.host, secret: creds.secret)
    }

    private func dispatchToTerminals(_ msg: WSMessage) {
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

// MARK: - PairingStore convenience

extension PairingStore {
    static func hasCredentials() -> Bool {
        (try? load()) != nil
    }
}
```

- [ ] **Step 2: Build and run on simulator**

```bash
cd apps/ios
xcodebuild build -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Smoke test**

1. Run on iPhone simulator
2. App shows QR scan screen (first launch)
3. After pairing (manual test with Mac agent running), app shows session list or offline state

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme TermCastiOS -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | grep -E "FAILED|passed|error:"
```

Expected: all test suites pass.

- [ ] **Step 5: Final commit**

```bash
cd ../..
git add apps/ios/TermCastiOS/App/TermCastiOSApp.swift
git commit -m "feat(ios): app entry point — navigation, WS connect, message dispatch to terminals"
```

---

## Done

iOS app complete. All features:
- [ ] QR scan pairing
- [ ] WebSocket connect with JWT
- [ ] Session list updates live
- [ ] SwiftTerm renders terminal output
- [ ] Keyboard toolbar with Ctrl/Esc/Tab/arrows
- [ ] Offline view with retry
- [ ] Exponential backoff reconnect

Next: `2026-04-05-phase-3-android-app.md`
