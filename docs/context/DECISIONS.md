# TermCast — Architecture Decisions

Running log of non-obvious decisions and the reasoning behind them.

---

## 2026-04-05

### ADR-001: PTY strategy — shell integration hooks, not raw fd sniffing

**Decision:** Use shell hooks (`.zshrc`/`.bashrc`/`config.fish`) for PTY I/O capture, not direct PTY device file injection.

**Context:** The original intent was to attach to existing PTY file descriptors from outside the owning process (vibetunnel-style). On macOS 14+:
- `TIOCSTI` ioctl (inject input to slave side) was removed in macOS 12
- Opening the PTY master fd (held by iTerm2/Terminal.app) requires a Mach task port, which requires `com.apple.security.get-task-allow` entitlement — Apple restricts this for App Store and notarized apps
- Reading from the PTY slave gives you outbound data direction (slave→master), not what we want

**Resolution:** Shell integration hooks achieve the same user experience:
- User opens any terminal → shell sources `.zshrc` → hook connects to TermCast's Unix socket → I/O piped via named pipes
- TermCast sees the session within 2 seconds of terminal open
- Fully bidirectional with zero privilege escalation
- One-time setup (paste one line to shell config)

This is the same mechanism used by iTerm2 shell integration, Warp blocks, and Zellij.

---

### ADR-002: SwiftNIO over Vapor for Mac WebSocket server

**Decision:** Use SwiftNIO directly, not Vapor.

**Context:** Both were listed as references in the project brief. Vapor is built on SwiftNIO.

**Reasoning:** A menu bar agent embedding a full HTTP framework (routing, middleware, templating, async DB) is wrong-sized. SwiftNIO gives the same async primitives and WebSocket channel handlers without the web framework overhead. Vapor adds ~10MB to the binary and dozens of transitive dependencies we don't need.

---

### ADR-003: SwiftTerm on iOS, xterm.js WebView on Android

**Decision:** Different terminal renderers per platform.

**Context:** The original spec specified xterm.js in a WebView on both platforms.

**iOS reasoning:** SwiftTerm is a native, well-maintained VT100/xterm emulator. It handles ANSI, colours, resize, and mouse natively. Using a WebView for terminal rendering on iOS when a native library exists is unnecessary overhead.

**Android reasoning:** No mature, Compose-compatible native terminal emulator exists for Android. JediTerm (JetBrains) is Java-heavy with no Compose bindings. xterm.js bundled locally (no CDN) is battle-tested at scale (VS Code, ttyd, Secure ShellFish web mode).

---

### ADR-004: Separate native apps (Swift iOS + Kotlin Android)

**Decision:** Two completely separate codebases, no React Native / Flutter / KMP.

**Context:** Original spec called for React Native Expo. User revised this during design.

**Reasoning:** Best performance and control. No JS bridge. SwiftTerm integration on iOS requires native Swift. The terminal rendering and keyboard toolbar are performance-sensitive paths — native is the right choice. Two codebases is manageable; shared assets (xterm.js, shell scripts, protocol schema) live in `shared/`.

---

### ADR-005: Monorepo structure

**Decision:** Single git repo for Mac, iOS, Android, and shared assets.

**Reasoning:** The three apps share:
- WebSocket protocol definition (`shared/protocol/`)
- xterm.js bundle (`shared/assets/xterm/`)
- Shell integration scripts (`shared/shell-integration/`)
- Documentation and design decisions

A monorepo avoids protocol drift (both clients and server reference the same JSON schema), simplifies cross-component issues, and enables unified CI.

No shared runtime code — Swift and Kotlin don't interop. Sharing is at the asset and documentation level only.
