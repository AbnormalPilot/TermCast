# TermCast

Broadcast live, bidirectional terminal sessions from your Mac to iOS or Android over Tailscale.

## Structure

- `apps/mac/` — Swift macOS 14+ menu bar app (SwiftNIO WebSocket server)
- `apps/ios/` — Swift iOS 16+ app (SwiftUI + SwiftTerm)
- `apps/android/` — Kotlin Android API 26+ app (Compose + xterm.js WebView)
- `shared/` — Protocol schema, xterm.js bundle, shell integration scripts
- `docs/` — Design spec, implementation plans, context tracking

## Setup

See `docs/superpowers/specs/2026-04-05-termcast-design.md` for full design.

Build order: Phase 0 → Phase 1 (Mac) → Phase 2 (iOS) → Phase 3 (Android)
