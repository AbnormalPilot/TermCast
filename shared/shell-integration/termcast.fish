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
