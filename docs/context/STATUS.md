# TermCast — Project Status

**Last Updated:** 2026-04-05  
**Current Phase:** 0 — Scaffold  
**Branch:** main

---

## Phase Status

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Monorepo scaffold, CLAUDE.md, design spec | Ready | Plan: phase-0-scaffold.md |
| 1 | Mac Agent — shell integration + SwiftNIO WS server | Complete | Plan: phase-1-mac-agent.md |
| 2 | iOS App — onboarding, SwiftTerm, reconnect | Ready | Plan: phase-2-ios-app.md |
| 3 | Android App — onboarding, xterm.js WebView, reconnect | Ready | Plan: phase-3-android-app.md |
| 4 | Tailscale integration + QR pairing end-to-end | Pending | Covered in Phase 1 Task 13 + 15 |
| 5 | Polish, error states, full test coverage | Pending | |

---

## Current Session Focus

Phase 1 (Mac Agent) complete. All 23 unit/integration tests passing.
Next: merge feature/build → main, then begin Phase 2 (iOS App).

---

## Key Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-05 | PTY strategy: shell integration hooks | TIOCSTI removed macOS 12; task port needs SIP disable. Hooks achieve same UX without privilege. |
| 2026-04-05 | WebSocket server: SwiftNIO | Vapor too heavy for a menu bar agent; SwiftNIO is what Vapor is built on |
| 2026-04-05 | iOS renderer: SwiftTerm | Native VT100 emulator, no WebView overhead on iOS |
| 2026-04-05 | Android renderer: xterm.js in WebView | No mature Compose-native terminal emulator exists |
| 2026-04-05 | Mobile: separate native apps (Swift + Kotlin) | Best performance, direct system access, no JS bridge |
| 2026-04-05 | Repo: monorepo | Shared protocol schema, xterm.js bundle, shell scripts, unified CI |
| 2026-04-05 | Auth: JWT HS256, QR pairing | Simple, secure, one-time setup |
| 2026-04-05 | Targets: macOS 14+, iOS 16+, Android API 26+ | Modern tooling, no back-compat debt |

---

## Open Questions

None — all resolved in design phase.

---

## Context Files

| File | Purpose |
|------|---------|
| `docs/superpowers/specs/2026-04-05-termcast-design.md` | Full design spec |
| `docs/context/STATUS.md` | This file — current state |
| `docs/context/smoke-tests.md` | Manual smoke test protocol (created in Phase 5) |
| `CLAUDE.md` | Project conventions for AI sessions |
