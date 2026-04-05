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
