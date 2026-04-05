# TermCast — Project Status

**Last Updated:** 2026-04-05  
**Current Phase:** Complete — Phase 5 (polish + error states)  
**Branch:** feature/phase-5-polish (merging → main)

---

## Phase Status

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Monorepo scaffold, CLAUDE.md, design spec | Complete — merged to main | Plan: phase-0-scaffold.md |
| 1 | Mac Agent — shell integration + SwiftNIO WS server | Complete — merged to main | Plan: phase-1-mac-agent.md |
| 2 | iOS App — onboarding, SwiftTerm, reconnect | Complete — merging to main | Plan: phase-2-ios-app.md |
| 3 | Android App — onboarding, xterm.js WebView, reconnect | Complete — merging to main | Plan: phase-3-android-app.md |
| 4 | Tailscale integration + QR pairing end-to-end | Complete — merging to main | Plan: phase-4-tailscale-pairing.md |
| 5 | Polish, error states, full test coverage | Complete — merging to main | Plan: phase-5-polish.md |

---

## Current Session Focus

Phase 5 complete. All three tasks shipped:
- T1: Mac port conflict detection — tries 7681→7685, persists chosen port in UserDefaults
- T2: iOS ring buffer replay — SessionTabView sends `attach` on first appear while connected
- T3: Manual smoke test protocol — 9 tests in docs/context/smoke-tests.md

All phases complete. Project ready for release.

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

### Testing Infrastructure (completed 2026-04-05)
- Mac: JWTManager MC/DC (8 vectors), RingBuffer MC/DC, KeychainStore, SessionBroadcaster, WSMessage, Security, Performance tests
- iOS: InputHandler MC/DC, ReconnectPolicy MC/DC, SessionStore (10 tests), WSMessage, Security tests; XCUITest onboarding (3 tests)
- Android: InputHandler MC/DC, ReconnectPolicy MC/DC, SessionViewModel (Turbine, 10 tests), WSMessage, XtermBridge, Security, Performance; Compose UI tests (6 tests)
- Shared: Cypress e2e for xterm.js bundle (11 tests)
- CI/CD: GitHub Actions for Mac, iOS, Android; coverage report workflow
- Regression manifest: 12 bugs mapped to catching tests

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
