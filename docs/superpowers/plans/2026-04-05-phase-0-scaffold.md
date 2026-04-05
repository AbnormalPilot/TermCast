# Phase 0: Monorepo Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the full monorepo directory structure, shared protocol schema, shell integration scripts, and xterm.js bundle that all three apps depend on.

**Architecture:** Single git repo with `apps/`, `shared/`, and `docs/` directories. No runtime code is shared between Swift and Kotlin — sharing is at the asset, script, and schema level only.

**Tech Stack:** POSIX sh (shell hooks), JSON Schema (protocol), xterm.js 5.3.0 (Android WebView bundle)

---

## File Map

```
termcast/
├── apps/
│   ├── mac/                         # (empty, Xcode project added in Phase 1)
│   ├── ios/                         # (empty, Xcode project added in Phase 2)
│   └── android/                     # (empty, Android Studio project added in Phase 3)
├── shared/
│   ├── protocol/
│   │   └── messages.json            # JSON Schema for all WebSocket messages
│   ├── assets/
│   │   └── xterm/
│   │       ├── VERSION              # Pinned xterm.js version
│   │       └── index.html           # Bundled xterm.js page (Android WebView)
│   └── shell-integration/
│       ├── termcast.sh              # zsh/bash hook (sources from .zshrc/.bashrc)
│       └── termcast.fish            # fish hook (sources from config.fish)
├── .gitignore
└── README.md
```

---

## Task 1: Create Directory Structure

**Files:**
- Create: `apps/mac/.gitkeep`
- Create: `apps/ios/.gitkeep`
- Create: `apps/android/.gitkeep`
- Create: `shared/protocol/.gitkeep`
- Create: `shared/assets/xterm/.gitkeep`
- Create: `shared/shell-integration/.gitkeep`

- [ ] **Step 1: Create all directories**

```bash
mkdir -p apps/mac apps/ios apps/android
mkdir -p shared/protocol shared/assets/xterm shared/shell-integration
touch apps/mac/.gitkeep apps/ios/.gitkeep apps/android/.gitkeep
```

- [ ] **Step 2: Verify structure**

```bash
find . -not -path './.git/*' -not -name '.gitkeep' | sort
```

Expected output:
```
.
./CLAUDE.md
./apps
./apps/android
./apps/ios
./apps/mac
./docs
./shared
./shared/assets
./shared/assets/xterm
./shared/protocol
./shared/shell-integration
```

---

## Task 2: WebSocket Protocol Schema

**Files:**
- Create: `shared/protocol/messages.json`

- [ ] **Step 1: Write the protocol schema**

```bash
cat > shared/protocol/messages.json << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TermCast WebSocket Protocol",
  "version": "1.0.0",
  "description": "All messages are JSON text frames. Terminal output bytes are base64-encoded.",

  "Session": {
    "type": "object",
    "required": ["id", "pid", "tty", "shell", "termApp", "cols", "rows", "isActive"],
    "properties": {
      "id":      { "type": "string", "format": "uuid" },
      "pid":     { "type": "integer" },
      "tty":     { "type": "string", "example": "ttys003" },
      "shell":   { "type": "string", "example": "zsh" },
      "termApp": { "type": "string", "example": "iTerm2" },
      "cols":    { "type": "integer", "default": 80 },
      "rows":    { "type": "integer", "default": 24 },
      "isActive":{ "type": "boolean" }
    }
  },

  "ServerMessages": {
    "sessions": {
      "description": "Sent immediately after successful WS connection",
      "fields": { "type": "sessions", "sessions": "[Session]" }
    },
    "session_opened": {
      "description": "New shell registered with the agent",
      "fields": { "type": "session_opened", "session": "Session" }
    },
    "session_closed": {
      "description": "Shell exited or pipe closed",
      "fields": { "type": "session_closed", "sessionId": "uuid" }
    },
    "output": {
      "description": "Terminal bytes from a session",
      "fields": { "type": "output", "sessionId": "uuid", "data": "base64" }
    },
    "resize": {
      "description": "Terminal dimensions changed on Mac side",
      "fields": { "type": "resize", "sessionId": "uuid", "cols": "int", "rows": "int" }
    },
    "ping": {
      "description": "Keepalive sent every 5 seconds",
      "fields": { "type": "ping" }
    }
  },

  "ClientMessages": {
    "attach": {
      "description": "Subscribe to a session. Triggers ring-buffer replay before live stream.",
      "fields": { "type": "attach", "sessionId": "uuid" }
    },
    "input": {
      "description": "Keystrokes to inject into the session",
      "fields": { "type": "input", "sessionId": "uuid", "data": "base64" }
    },
    "resize": {
      "description": "Mobile viewport size changed; Mac sends SIGWINCH to shell",
      "fields": { "type": "resize", "sessionId": "uuid", "cols": "int", "rows": "int" }
    },
    "pong": {
      "description": "Response to server ping",
      "fields": { "type": "pong" }
    }
  },

  "Connection": {
    "url": "wss://{tailscale-hostname}",
    "auth": "Authorization: Bearer {JWT}",
    "jwtAlgorithm": "HS256",
    "jwtExpiry": "30 days",
    "pingInterval": "5s",
    "reconnectBackoff": "1s, 2s, 4s, 8s, 16s, 32s, 60s (cap)"
  }
}
EOF
```

- [ ] **Step 2: Verify it's valid JSON**

```bash
python3 -m json.tool shared/protocol/messages.json > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

---

## Task 3: Shell Integration — zsh/bash Hook

**Files:**
- Create: `shared/shell-integration/termcast.sh`

- [ ] **Step 1: Write the POSIX sh hook**

```bash
cat > shared/shell-integration/termcast.sh << 'HOOK'
# TermCast shell integration
# Add to ~/.zshrc or ~/.bashrc:
#   [ -f ~/.termcast/hook.sh ] && source ~/.termcast/hook.sh

_termcast_register() {
    local helper="$HOME/.termcast/bin/termcast-hook"
    [ -x "$helper" ] || return 0          # Agent not installed — skip silently

    local tty_dev
    tty_dev=$(tty 2>/dev/null) || return 0 # Not an interactive shell — skip

    local pid=$$
    local out_pipe="/tmp/termcast/$pid.out"

    mkdir -p /tmp/termcast
    mkfifo "$out_pipe" 2>/dev/null || return 0
    chmod 600 "$out_pipe"

    # Register with TermCast agent (background, non-blocking)
    "$helper" \
        --pid    "$pid" \
        --tty    "$tty_dev" \
        --shell  "$(basename "${SHELL:-sh}")" \
        --term   "${TERM_PROGRAM:-unknown}" \
        --out-pipe "$out_pipe" &

    # Tee all shell output to the named pipe
    exec > >(tee -a "$out_pipe") 2>&1

    # Cleanup named pipe on shell exit
    trap 'rm -f "$out_pipe" 2>/dev/null' EXIT
}

_termcast_register
unset -f _termcast_register
HOOK
chmod +x shared/shell-integration/termcast.sh
```

- [ ] **Step 2: Verify the script has no syntax errors**

```bash
bash -n shared/shell-integration/termcast.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

## Task 4: Shell Integration — fish Hook

**Files:**
- Create: `shared/shell-integration/termcast.fish`

- [ ] **Step 1: Write the fish hook**

```bash
cat > shared/shell-integration/termcast.fish << 'HOOK'
# TermCast shell integration for fish
# Add to ~/.config/fish/config.fish:
#   if test -f ~/.termcast/hook.fish; source ~/.termcast/hook.fish; end

function _termcast_register
    set -l helper "$HOME/.termcast/bin/termcast-hook"
    test -x "$helper" || return 0

    set -l tty_dev (tty 2>/dev/null)
    test -n "$tty_dev" || return 0

    set -l pid (echo %self)
    set -l out_pipe "/tmp/termcast/$pid.out"

    mkdir -p /tmp/termcast
    mkfifo "$out_pipe" 2>/dev/null
    chmod 600 "$out_pipe"

    $helper \
        --pid     "$pid" \
        --tty     "$tty_dev" \
        --shell   "fish" \
        --term    "$TERM_PROGRAM" \
        --out-pipe "$out_pipe" &

    # fish doesn't support exec tee redirection directly
    # Output capture runs via the hook binary monitoring the TTY
end

_termcast_register
functions -e _termcast_register
HOOK
```

- [ ] **Step 2: Verify no obvious errors**

```bash
grep -n "set -l" shared/shell-integration/termcast.fish | head -5
```

Expected: shows the `set -l` lines without errors.

---

## Task 5: xterm.js Bundle

**Files:**
- Create: `shared/assets/xterm/VERSION`
- Create: `shared/assets/xterm/index.html`

- [ ] **Step 1: Pin the version**

```bash
echo "5.3.0" > shared/assets/xterm/VERSION
```

- [ ] **Step 2: Download xterm.js from CDN and bundle locally**

```bash
cd shared/assets/xterm

# Download xterm.js and its CSS (no CDN at runtime)
curl -fsSL "https://unpkg.com/xterm@5.3.0/lib/xterm.js" -o xterm.js
curl -fsSL "https://unpkg.com/xterm@5.3.0/css/xterm.css" -o xterm.css
curl -fsSL "https://unpkg.com/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js" -o xterm-addon-fit.js

cd ../../..
```

- [ ] **Step 3: Write the HTML wrapper page**

```bash
cat > shared/assets/xterm/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #000; overflow: hidden; }
    #terminal { width: 100vw; height: 100vh; }
    .xterm-viewport::-webkit-scrollbar { display: none; }
  </style>
  <link rel="stylesheet" href="xterm.css">
</head>
<body>
  <div id="terminal"></div>
  <script src="xterm.js"></script>
  <script src="xterm-addon-fit.js"></script>
  <script>
    const term = new Terminal({
      fontFamily: 'Menlo, Consolas, "DejaVu Sans Mono", monospace',
      fontSize: 13,
      theme: { background: '#000000', foreground: '#ffffff' },
      allowProposedApi: true,
      scrollback: 5000
    });

    const fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open(document.getElementById('terminal'));
    fitAddon.fit();

    // Send input to Android via JavascriptInterface
    term.onData(data => {
      if (window.TermCastBridge) {
        TermCastBridge.onInput(btoa(unescape(encodeURIComponent(data))));
      }
    });

    // Notify Android when terminal is resized
    term.onResize(({ cols, rows }) => {
      if (window.TermCastBridge) {
        TermCastBridge.onResize(cols, rows);
      }
    });

    window.addEventListener('resize', () => fitAddon.fit());

    // Called by Android to write output bytes (base64-encoded)
    window.termWrite = function(base64) {
      try {
        const bytes = atob(base64);
        const arr = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
        term.write(arr);
      } catch(e) { console.error('termWrite error', e); }
    };

    // Called by Android to update terminal dimensions
    window.termResize = function(cols, rows) {
      term.resize(cols, rows);
    };

    // Signal ready
    if (window.TermCastBridge) TermCastBridge.onReady();
  </script>
</body>
</html>
HTML
```

- [ ] **Step 4: Verify all files exist**

```bash
ls -lh shared/assets/xterm/
```

Expected: `VERSION`, `xterm.js`, `xterm.css`, `xterm-addon-fit.js`, `index.html`

---

## Task 6: .gitignore and README

**Files:**
- Modify: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write .gitignore**

```bash
cat > .gitignore << 'EOF'
# macOS
.DS_Store
*.xcuserstate
xcuserdata/
*.xcworkspace/xcuserdata/
.build/
DerivedData/

# iOS / macOS Xcode
*.ipa
*.dSYM.zip
*.dSYM

# Android
*.iml
.gradle/
local.properties
.idea/
*.apk
*.aab
build/
captures/
.externalNativeBuild/
.cxx/

# Swift
.swiftpm/
*.o
*.d

# Node (xterm.js dev tools if ever needed)
node_modules/

# TermCast runtime
/tmp/termcast/
~/.termcast/

# Secrets
*.p12
*.mobileprovision
GoogleService-Info.plist
google-services.json
EOF
```

- [ ] **Step 2: Write README**

```bash
cat > README.md << 'EOF'
# TermCast

Broadcast live, bidirectional terminal sessions from your Mac to iOS or Android over Tailscale.

## Structure

```
apps/mac/        Swift macOS 14+ menu bar app (SwiftNIO WebSocket server)
apps/ios/        Swift iOS 16+ app (SwiftUI + SwiftTerm)
apps/android/    Kotlin Android API 26+ app (Compose + xterm.js WebView)
shared/          Protocol schema, xterm.js bundle, shell integration scripts
docs/            Design spec, implementation plans, context tracking
```

## Setup

See `docs/superpowers/specs/2026-04-05-termcast-design.md` for full design.

Build order: Phase 0 (this) → Phase 1 (Mac) → Phase 2 (iOS) → Phase 3 (Android)
EOF
```

- [ ] **Step 3: Commit scaffold**

```bash
git add .
git commit -m "feat: monorepo scaffold — dirs, protocol schema, shell hooks, xterm.js bundle"
```

Expected: commit with ~8 new files.

---

## Done

Scaffold complete. Next: `2026-04-05-phase-1-mac-agent.md`
