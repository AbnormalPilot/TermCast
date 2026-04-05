# TermCast — CLAUDE.md

Project-level conventions and context for AI-assisted development.

---

## What This Project Is

TermCast is a monorepo containing three native apps that broadcast live, bidirectional terminal sessions from a Mac to iOS and Android devices over Tailscale.

- **apps/mac/** — Swift macOS 14+ menu bar app (NSStatusItem, SwiftNIO WebSocket server)
- **apps/ios/** — Swift iOS 16+ app (SwiftUI + SwiftTerm)
- **apps/android/** — Kotlin Android API 26+ app (Jetpack Compose + xterm.js in WebView)
- **shared/** — Protocol schema, xterm.js bundle, shell integration scripts

## Design Spec

Full design: `docs/superpowers/specs/2026-04-05-termcast-design.md`

Key decisions recorded there:
- PTY strategy: shell integration hooks (no SIP/privilege needed)
- WebSocket server: SwiftNIO (not Vapor)
- iOS renderer: SwiftTerm (native, no WebView)
- Android renderer: xterm.js in bundled WebView
- Auth: JWT HS256, shared secret via QR pairing
- Network: Tailscale Serve, permanent hostname, no LAN/WAN logic

## Implementation Plans

See `docs/superpowers/plans/` — created as each phase begins.

## Context Tracking

See `docs/context/` — session logs, decisions, smoke tests, open questions.
**Always check `docs/context/STATUS.md` at the start of each session.**

---

## Code Conventions

### General
- Immutable data patterns throughout — no in-place mutation
- Files max 800 lines, functions max 50 lines
- Handle errors explicitly at every level — no silent swallowing
- No hardcoded values — use constants or config

### Mac (Swift)
- Swift Concurrency (async/await, actors) throughout — no completion handlers
- SwiftNIO for all networking — no URLSession WebSocket on the server side
- `@MainActor` for all UI updates
- Structured concurrency: `TaskGroup` for fan-out broadcasting

### iOS (Swift)
- SwiftUI + `@Observable` (iOS 17 macro) — no `ObservableObject`
- `Network.framework` for WebSocket client — not third-party
- Keychain via `Security.framework` directly — no wrapper libraries
- SwiftTerm: never call terminal APIs off main thread

### Android (Kotlin)
- Coroutines + StateFlow everywhere — no RxJava, no LiveData
- Jetpack Compose — no XML layouts
- OkHttp for WebSocket — already battle-tested for this use case
- `@JavascriptInterface` methods annotated and documented
- EncryptedSharedPreferences for all credential storage

### Shared
- WebSocket protocol defined in `shared/protocol/messages.json` (JSON Schema)
- Shell hook scripts must be POSIX sh compatible (not bash-only)
- xterm.js version pinned in `shared/assets/xterm/VERSION`

---

## Testing Requirements

- Unit test coverage: 80% minimum
- TDD workflow: write test first (RED), implement (GREEN), refactor (IMPROVE)
- No E2E tests across Mac↔phone — too many moving parts
- Smoke test protocol: `docs/context/smoke-tests.md`

---

## Git Conventions

Commit format:
```
<type>(<scope>): <description>

Types: feat, fix, refactor, docs, test, chore, perf
Scopes: mac, ios, android, shared, docs
```

Examples:
- `feat(mac): add session ring buffer with 64KB cap`
- `fix(ios): handle JWT expiry with graceful re-auth`
- `chore(shared): pin xterm.js to 5.3.0`

---

## Project Status

Updated each session. Current status always in `docs/context/STATUS.md`.

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Monorepo scaffold, CLAUDE.md, docs | In Progress |
| 1 | Mac Agent — shell integration + WebSocket server | Pending |
| 2 | iOS App — onboarding, terminal, reconnect | Pending |
| 3 | Android App — onboarding, terminal, reconnect | Pending |
| 4 | Tailscale integration + QR pairing | Pending |
| 5 | Polish, error states, testing | Pending |
