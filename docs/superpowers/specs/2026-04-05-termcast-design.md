# TermCast — Design Spec
**Date:** 2026-04-05  
**Status:** Approved  
**Author:** Himanshu Dubey

---

## Overview

TermCast is a macOS menu bar app (Swift) paired with native iOS (SwiftUI) and Android (Kotlin) apps that broadcasts live, bidirectional terminal sessions from a Mac to any paired device over Tailscale — from anywhere in the world, with zero network-switching logic.

---

## Goals

- Open any terminal on your Mac → it appears on your phone within 2 seconds
- Type from your phone → keystrokes arrive in the Mac terminal
- Works on WiFi, 4G, roaming — Tailscale handles routing invisibly
- One-time setup: install TermCast, add shell hook, scan QR code
- No root, no SIP disable, no network configuration

## Non-Goals

- No mDNS/Bonjour discovery
- No ngrok or manual tunnel setup
- No LAN vs WAN detection or switching
- No Tailscale SDK in mobile apps (Tailscale VPN extension handles routing)
- No screen sharing — terminals only
- No attaching to other users' processes

---

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Mac (macOS 14+)                                        │
│                                                         │
│  ┌──────────────┐    Unix socket    ┌────────────────┐  │
│  │  Shell Hook  │ ──────────────▶  │  TermCast      │  │
│  │  (zsh/bash/  │ ◀────────────── │  Agent         │  │
│  │   fish)      │  stdin pipe      │  (NSStatusItem) │  │
│  └──────────────┘                  │                │  │
│         │                          │  SwiftNIO WS   │  │
│   libproc/sysctl                   │  :7681         │  │
│   (process meta)                   │  64KB ring buf │  │
│                                    │  JWT auth      │  │
│                                    └───────┬────────┘  │
│                                            │           │
│                                    Tailscale Serve     │
└────────────────────────────────────────────┼───────────┘
                                             │ wss://macbook.ts.net
                         ┌───────────────────┼────────────────────┐
                         │                   │                    │
                  ┌──────▼──────┐    ┌───────▼──────┐
                  │  iOS App    │    │ Android App  │
                  │  SwiftUI    │    │  Compose     │
                  │  SwiftTerm  │    │ WV+xterm.js  │
                  │  Keychain   │    │ EncryptedSP  │
                  └─────────────┘    └──────────────┘
```

---

## Component 1: Mac Agent

### Technology
- Swift, macOS 14+, `LSUIElement = YES` (no Dock icon)
- SwiftNIO for embedded WebSocket server
- No XPC helpers, no privilege escalation

### Module Structure

```
TermCastApp
├── MenuBarController        // NSStatusItem, session list, badge, enable/disable
├── SessionRegistry          // source of truth: [SessionID: Session]
├── ShellIntegration
│   ├── Installer            // writes hook to .zshrc/.bashrc/config.fish at first launch
│   └── SocketServer         // Unix domain socket at ~/.termcast/agent.sock
├── SessionManager
│   ├── PTYSession           // one per registered shell: pipes, ring buffer, metadata
│   ├── ProcessInspector     // libproc/sysctl: PID → terminal app name, window title
│   └── RingBuffer           // 64KB circular buffer per session
├── WebSocketServer          // SwiftNIO on :7681
│   ├── JWTMiddleware        // HS256 validate on WS upgrade
│   ├── SessionBroadcaster   // fan-out output bytes to all attached clients
│   └── InputRouter          // route client input → correct session stdin pipe
└── TailscaleSetup           // first-launch: check install, run serve, get hostname, QR
```

### Session Lifecycle

```
Shell starts → sources .zshrc hook
  → hook connects to ~/.termcast/agent.sock
  → sends: { pid, ppid, tty, term, shell }
  → SocketServer creates PTYSession
    → ProcessInspector enriches with terminal app name
    → RingBuffer allocated
    → MenuBar badge increments
  → hook execs with I/O redirected through named pipes
    → TermCast reads output pipe → RingBuffer + broadcast
    → TermCast writes to input pipe → shell stdin

Shell exits → pipes close → PTYSession tombstoned → clients notified
```

### Shell Hook (installed to ~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish)

~15 lines of POSIX sh. Connects to `~/.termcast/agent.sock`, sends session metadata, redirects I/O via named pipes in `/tmp/termcast/<pid>.{in,out}`. Silent no-op if socket unreachable — shell opens normally.

### Menu Bar UI

- Status icon with live client count badge
- Dropdown: session list (terminal app icon + shell name per session)
- Per-session: toggle broadcast on/off, "Copy attach URL"
- Footer: client count, Tailscale hostname, Preferences, Quit

### First-Launch Wizard

1. Check Tailscale installed → prompt install if not
2. Run `tailscale serve 7681` to set up proxy
3. Run `tailscale status --json` → extract `Self.DNSName` as permanent hostname
4. Generate 256-bit random JWT secret → store in Keychain
5. Generate QR code encoding `{ host, secret }` → display in setup window
6. Install shell hook to detected shell config files

### Key Constraints

- Named pipes live in `/tmp/termcast/<pid>.{in,out}`, cleaned up on session close
- Sessions survive TermCast restart: re-scan `/tmp/termcast/` on launch
- SIGWINCH forwarded to shell on client resize
- Port 7681 default; increments to 7682+ if in use (persisted in UserDefaults)

---

## Component 2: iOS App

### Technology
- Swift, SwiftUI, iOS 16+
- SwiftTerm for native terminal rendering
- Network.framework for WebSocket client
- Keychain for credential storage
- AVFoundation for QR scanning

### Module Structure

```
TermCastiOS
├── Onboarding
│   ├── QRScanView           // AVFoundation camera, decodes host+secret JSON
│   └── PairingStore         // Keychain: host, JWT secret
├── Connection
│   ├── WSClient             // Network.framework NWConnection, WS framing
│   ├── ReconnectPolicy      // exponential backoff: 1s→2s→4s→...→60s cap
│   └── PingPong             // 5s keepalive, detect stale connection
├── Sessions
│   ├── SessionListView      // tab bar: all available sessions
│   ├── SessionTab           // one tab per attached session
│   └── SessionStore         // @Observable: [SessionID: SessionState]
├── Terminal
│   ├── TerminalView         // SwiftTerm TerminalView wrapped in SwiftUI
│   ├── KeyboardToolbar      // Ctrl (sticky), Esc, Tab, ↑↓←→ via inputAccessoryView
│   └── InputHandler         // encodes keystrokes → ANSI sequences → WSClient
└── Offline
    └── OfflineView          // "Mac offline" full-screen state, retry button
```

### Terminal Rendering

SwiftTerm is a native VT100/xterm-compatible emulator. Handles ANSI colours, bold/italic, resize, mouse events. No WebView, no xterm.js on iOS — pure native.

### Keyboard Toolbar

Persistent toolbar above system keyboard (`inputAccessoryView`). Ctrl is sticky — tap it, then tap a letter → correct control sequence. Arrow keys send ANSI escape sequences (`\x1b[A` etc.) directly.

### State Flow

```
Launch → Keychain check
  No credentials → QRScanView
  Credentials found → WSClient.connect()
    Success → SessionListView
    Failure → OfflineView + backoff retry
```

### Limits
- Max 8 simultaneous session tabs

---

## Component 3: Android App

### Technology
- Kotlin, Jetpack Compose, Android API 26+
- OkHttp for WebSocket client
- xterm.js 5.x bundled in `assets/xterm/` (zero CDN)
- WebView for terminal rendering
- CameraX + ML Kit for QR scanning
- EncryptedSharedPreferences for credentials

### Module Structure

```
TermCastAndroid
├── onboarding
│   ├── QRScanScreen         // CameraX + ML Kit barcode scanning
│   └── PairingRepository    // EncryptedSharedPreferences: host, JWT secret
├── connection
│   ├── WSClient             // OkHttp WebSocket, coroutine StateFlow
│   ├── ReconnectPolicy      // exponential backoff: 1s→2s→4s→...→60s cap
│   └── PingPong             // 5s keepalive via coroutine timer
├── sessions
│   ├── SessionListScreen    // tab row: available sessions
│   ├── SessionTab           // one tab per attached session
│   └── SessionViewModel     // StateFlow: SessionState per session
├── terminal
│   ├── TerminalScreen       // AndroidView wrapping WebView
│   ├── XtermBridge          // Kotlin↔xterm.js via evaluateJavascript + @JavascriptInterface
│   ├── KeyboardToolbar      // Compose Row: Ctrl (sticky), Esc, Tab, ↑↓←→
│   └── InputHandler         // encodes keystrokes → posts to WSClient
└── offline
    └── OfflineScreen        // "Mac offline" state, retry button
```

### Terminal Rendering

WebView loads `assets/xterm/index.html` (xterm.js bundled, no CDN). `XtermBridge` handles:
- **Output** → `webView.evaluateJavascript("term.write('${base64}')")`
- **Input** → JS `term.onData` → `@JavascriptInterface` → `WSClient`
- **Resize** → `term.onResize` → WebSocket resize message

Why WebView on Android: no mature, Compose-compatible native terminal emulator exists. JediTerm is Java-heavy with no Compose integration. xterm.js bundled locally is battle-tested (VS Code, ttyd, dozens of production apps).

### State Flow
Identical to iOS: Credential check → QR scan if empty → connect → SessionList or Offline.

---

## WebSocket Protocol

### Connection
Client connects to `wss://macbook.ts.net` (Tailscale Serve → localhost:7681).  
JWT sent in `Authorization: Bearer <token>` header on WebSocket upgrade request.

### Message Types — Mac → Client

| Type | Fields | Description |
|------|--------|-------------|
| `sessions` | `sessions: [Session]` | Full session list, sent on connect |
| `session_opened` | `session: Session` | New shell registered |
| `session_closed` | `sessionId` | Shell exited |
| `output` | `sessionId`, `data: base64` | Terminal bytes, base64-encoded, JSON text frame |
| `resize` | `sessionId`, `cols`, `rows` | Terminal size changed |
| `ping` | — | Keepalive every 5s |

### Message Types — Client → Mac

| Type | Fields | Description |
|------|--------|-------------|
| `attach` | `sessionId` | Subscribe + triggers ring buffer replay |
| `input` | `sessionId`, `data: base64` | Keystrokes → shell stdin pipe |
| `resize` | `sessionId`, `cols`, `rows` | Viewport changed → SIGWINCH |
| `pong` | — | Keepalive response |

### Auth

- Mac generates 256-bit random secret at first launch → Keychain
- JWTs signed HS256, expire after 30 days, refreshed on app open
- QR code encodes: `{ "host": "macbook.ts.net", "secret": "<hex>" }`
- Invalid JWT on upgrade → 401, connection rejected
- JWT rejected on mobile → clear credentials → QR scan

### Ring Buffer

- 64KB circular byte buffer per session
- On `attach`: full buffer replayed before live stream begins
- On session close: buffer flushed, session marked tombstoned (retained 5 min for late reconnects)

---

## Error Handling

### Mac Agent

| Scenario | Handling |
|---|---|
| Shell hook can't connect to socket | Silent no-op — shell opens normally, unregistered |
| Session pipe EOF (shell crash) | PTYSession tombstoned, clients notified via `session_closed` |
| Client disconnects | Session alive, ring buffer fills, client can rejoin |
| Tailscale not installed | Setup wizard blocks at step 1, shows install link |
| Port 7681 in use | Increment to 7682, persist in UserDefaults |
| TermCast crash/restart | Re-scan `/tmp/termcast/` on launch to recover live sessions |

### Mobile (iOS + Android)

| Scenario | Handling |
|---|---|
| WebSocket connect fails | OfflineView + exponential backoff (1s→60s) |
| Ping timeout (5s) | Treat as disconnect → reconnect flow |
| JWT rejected (401) | Clear credentials → QR scan |
| Session closed mid-view | Tab shows "Session ended" banner, scroll history preserved |
| Reconnect | `attach` always replays ring buffer — client catches up |

---

## Testing Strategy

### Mac Agent
- **Unit:** `RingBuffer` overflow/wrap, `JWTMiddleware` accept/reject, `ProcessInspector` PID parsing
- **Integration:** Full session lifecycle via test shell script connecting to Unix socket
- No UI tests for menu bar

### iOS
- **Unit:** `ReconnectPolicy` backoff math, `InputHandler` control sequence encoding, `PairingStore` Keychain round-trip
- **UI:** XCTest snapshot tests on `KeyboardToolbar`, `OfflineView`
- **Integration:** Mock `WSClient` driving SwiftTerm output

### Android
- **Unit:** `ReconnectPolicy`, `XtermBridge` message encoding, `PairingRepository`
- **UI:** Compose screenshot tests on toolbar, offline screen
- **Integration:** Mock `WSClient` coroutine flow driving WebView bridge

### No E2E Tests Cross-Platform
Too many moving parts (Tailscale, real PTY, two OSes). Manual smoke test checklist maintained in `docs/context/smoke-tests.md`.

---

## Repository Structure

Monorepo — single git repo, all components, shared assets and tooling.

```
termcast/
├── apps/
│   ├── mac/                 // Xcode project — Swift macOS 14+ menu bar app
│   ├── ios/                 // Xcode project — Swift iOS 16+ app
│   └── android/             // Android Studio project — Kotlin Android API 26+
├── shared/
│   ├── protocol/            // WebSocket message type definitions (JSON schema)
│   ├── assets/
│   │   └── xterm/           // xterm.js 5.x bundle (used by Android WebView)
│   └── shell-integration/   // Shell hook scripts (zsh/bash/fish)
├── docs/
│   ├── superpowers/
│   │   ├── specs/           // Design specs (this file)
│   │   └── plans/           // Implementation plans
│   └── context/             // Session context, decisions, smoke tests
└── CLAUDE.md                // Project conventions and AI context
```

**Monorepo benefits:**
- Single source of truth for WebSocket protocol spec (`shared/protocol/`)
- Shell integration scripts maintained once, referenced by Mac app installer
- xterm.js bundle versioned once, consumed by Android
- Unified CI/CD pipeline across all three apps
- Cross-component issues and version bumps in one place

**No shared runtime code** between Swift and Kotlin — languages don't interop directly. Sharing is at the asset, script, and documentation level.

---

## Open Questions (None — all resolved)

All architectural decisions finalized during brainstorming:
- PTY strategy: shell integration hooks (no SIP/privilege needed)
- WebSocket server: SwiftNIO (not Vapor)
- iOS renderer: SwiftTerm (native, no WebView)
- Android renderer: xterm.js in bundled WebView
- Mobile framework: separate native apps (Swift iOS, Kotlin Android)
- Network: Tailscale Serve, permanent hostname, no LAN/WAN switching
- Auth: JWT HS256, shared secret via QR
- Target: macOS 14+, iOS 16+, Android API 26+
