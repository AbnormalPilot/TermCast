# TermCast — Manual Smoke Test Protocol

**Purpose:** End-to-end verification that cannot be automated (requires real Tailscale, real Mac PTY, real phone).  
**Run before:** Every release merge, after any change to Mac WebSocket server or shell integration.

---

## Prerequisites

- Mac running macOS 14+ with TermCast built and running
- Tailscale installed and authenticated on the Mac
- iOS simulator or real device with TermCastiOS installed
- Android emulator or real device with TermCast Android installed
- Both mobile clients on Tailscale (or on same LAN with Tailscale routing)

---

## Smoke Test 1 — First Launch + Pairing (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Fresh install: delete app, delete Keychain entry for `jwt-secret`, relaunch TermCast | QR code window appears |
| 2 | Open iOS app (no stored credentials) | QR scan screen appears |
| 3 | Scan QR code with iOS app | iOS navigates to session list |
| 4 | Open a terminal on Mac (`zsh` or `bash` session) | Session appears in iOS session list within 2 seconds |
| 5 | Tap session in iOS app | Terminal view opens; last 64KB of output is replayed (ring buffer) |
| 6 | Type a command in the iOS keyboard toolbar | Command appears in Mac terminal |
| 7 | Run a long command on Mac (e.g. `ls -la /usr/bin`) | Output scrolls in iOS terminal view |

---

## Smoke Test 2 — First Launch + Pairing (Android)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Fresh install Android app | QR scan screen appears |
| 2 | Scan QR code from Mac menu bar ("Pair another device…") | Android navigates to session list |
| 3 | Tap session | xterm.js WebView renders terminal output |
| 4 | Type from Android soft keyboard | Input arrives in Mac terminal |

---

## Smoke Test 3 — Reconnect + Ring Buffer Replay

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS app connected, session open | Terminal shows live output |
| 2 | Put iOS app in background for 30+ seconds | App stays alive; NWConnection times out |
| 3 | Bring iOS app back to foreground | OfflineView appears briefly, then reconnects |
| 4 | Tap session again | Ring buffer replayed — history visible, not blank |

---

## Smoke Test 4 — Auth Failure Re-pairing (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS connected | Session list visible |
| 2 | On Mac: delete Keychain entry and relaunch TermCast (new JWT secret generated) | iOS shows OfflineView with "Unpair — Scan QR again" button |
| 3 | Tap "Unpair — Scan QR again" | QR scan screen appears |
| 4 | Scan new QR code | iOS reconnects and shows session list |

---

## Smoke Test 5 — Auth Failure Re-pairing (Android)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Android connected | Session list visible |
| 2 | On Mac: delete Keychain entry and relaunch TermCast | Android automatically clears credentials and shows QR scan screen |
| 3 | Scan new QR code | Android reconnects |

---

## Smoke Test 6 — Port Conflict Recovery

| Step | Action | Expected |
|------|--------|----------|
| 1 | Pre-occupy port 7681: `nc -l 7681 &` in a Mac terminal | Port in use |
| 2 | Launch TermCast | App starts without error; server binds to 7682 |
| 3 | Verify in Console.app or `lsof -i :7682` | TermCast process listening on 7682 |
| 4 | Kill the nc process, relaunch TermCast | App starts on 7681 again (preferred port, now free) |

---

## Smoke Test 7 — Session Ended Banner

| Step | Action | Expected |
|------|--------|----------|
| 1 | iOS app open with active session tab | Terminal shows live output |
| 2 | On Mac: `exit` in the terminal session | iOS shows red "Session ended" banner in top-right of terminal view |
| 3 | History remains visible below the banner | Terminal output is not cleared |

---

## Smoke Test 8 — Multi-session

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open 3 terminal sessions on Mac | iOS session list shows all 3 |
| 2 | Tap each session | Each has independent terminal history |
| 3 | Type in each session | Input reaches the correct Mac terminal |
| 4 | Close one session on Mac | That session's tab shows "Session ended"; others unaffected |

---

## Smoke Test 9 — Mac Restart Recovery

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open 2 terminal sessions, connect iOS | Both sessions visible |
| 2 | Kill TermCast process (Cmd+Q or force quit) | iOS shows OfflineView |
| 3 | Relaunch TermCast | TermCast re-scans `/tmp/termcast/` for live sessions |
| 4 | iOS reconnects automatically | Both sessions restored in session list |

---

## Pass Criteria

All 9 smoke tests pass without error. No crash logs in Console.app. iOS and Android apps do not show unexpected blank screens or stuck states.
