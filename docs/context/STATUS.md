# TermCast — Project Status

**Last Updated:** 2026-04-05  
**Current Phase:** 0 — Scaffold  
**Branch:** main

---

## Phase Status

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Monorepo scaffold, CLAUDE.md, design spec | In Progress | Design approved, writing plan next |
| 1 | Mac Agent — shell integration + SwiftNIO WS server | Pending | |
| 2 | iOS App — onboarding, SwiftTerm, reconnect | Pending | |
| 3 | Android App — onboarding, xterm.js WebView, reconnect | Pending | |
| 4 | Tailscale integration + QR pairing end-to-end | Pending | |
| 5 | Polish, error states, full test coverage | Pending | |

---

## Current Session Focus

Brainstorming complete. Design spec written and approved.
Next: implementation plan via `writing-plans` skill.

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
