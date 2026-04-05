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

### Commit Format

```
<type>(<scope>): <description>

Types: feat, fix, refactor, docs, test, chore, perf
Scopes: mac, ios, android, shared, docs
```

Examples:
- `feat(mac): add session ring buffer with 64KB cap`
- `fix(ios): handle JWT expiry with graceful re-auth`
- `chore(shared): pin xterm.js to 5.3.0`

### Branching Strategy

```
main
 └── feature/phase-0-scaffold     → merged to main when Phase 0 complete
 └── feature/phase-1-mac-agent    → merged to main when Phase 1 complete + tests green
 └── feature/phase-2-ios-app      → merged to main when Phase 2 complete + tests green
 └── feature/phase-3-android-app  → merged to main when Phase 3 complete + tests green
```

- **`main`** — always releasable; only receives merges from completed, tested phase branches
- **`feature/phase-N-*`** — one branch per phase; all task commits land here
- **No direct commits to `main`** — all work goes through feature branches
- **Hotfixes** — branch off `main` as `fix/<description>`, merge back to both `main` and the active feature branch

### When to Merge

| Event | Action |
|-------|--------|
| Phase scaffold complete (all tasks done, all tests pass) | Merge `feature/phase-N-*` → `main` with `--no-ff`; tag `vN.0-phase-N` |
| Mid-phase checkpoint (e.g. after core models/networking) | No merge — keep on feature branch; push to remote for backup |
| Bug found on a released phase | Branch `fix/*` from `main`, fix, merge back to `main` + active feature branch |
| New session starts on same phase | Continue on existing feature branch — do not create a new branch |

### Merge Procedure

```bash
# When a phase is complete and tests pass:
git checkout main
git merge --no-ff feature/phase-N-name -m "chore: merge phase N — <brief summary>"
git tag vN.0-phase-N
git push origin main --tags

# Keep the feature branch for reference (don't delete)
```

### Current Worktree

All active development happens in `.worktrees/build` on branch `feature/build`.
When Phase 1 is complete, merge `feature/build` → `main`, then create `feature/phase-2-ios-app` for Phase 2.

---

## Project Status

Updated each session. Current status always in `docs/context/STATUS.md`.

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Monorepo scaffold, CLAUDE.md, docs | Complete — merged to main |
| 1 | Mac Agent — shell integration + WebSocket server | In Progress — `feature/build` |
| 2 | iOS App — onboarding, terminal, reconnect | Pending |
| 3 | Android App — onboarding, terminal, reconnect | Pending |
| 4 | Tailscale integration + QR pairing | Pending |
| 5 | Polish, error states, testing | Pending |
