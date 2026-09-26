#!/bin/sh
# guile-repl-paths.sh --- derive a project's REPL ports and log directory.
#
# Sourced by the other scripts, or run directly to see what this project gets:
#
#   . bin/guile-repl-paths.sh          # sets GUILE_REPL_{SLUG,DIR,PORT,PROXY_PORT}
#   ./bin/guile-repl-paths.sh          # prints them
#
# The slug follows the ~/.claude/projects convention exactly: every "/" and "."
# in the absolute path becomes "-", so the leading slash leaves a leading dash.
#   /home/u/ghq/github.com/o/r  ->  -home-u-ghq-github-com-o-r
#
# The port is derived from the slug, so a project always gets the same port and
# two projects rarely collide. It is a convention, not a reservation: check the
# port is free before trusting it (guile-repl-server.sh does).

GUILE_REPL_ROOT=${GUILE_REPL_ROOT:-$HOME/.guile-skill}
GUILE_REPL_SLUG=$(pwd | tr '/.' '--')
GUILE_REPL_DIR="$GUILE_REPL_ROOT/projects/$GUILE_REPL_SLUG"

# cksum is POSIX and present on FreeBSD, macOS and Linux; base 37000 keeps us
# in the IANA dynamic range and clear of the usual development ports.
GUILE_REPL_PORT=${GUILE_REPL_PORT:-$((37000 + $(printf '%s' "$GUILE_REPL_SLUG" | cksum | cut -d' ' -f1) % 900))}
GUILE_REPL_PROXY_PORT=$((GUILE_REPL_PORT + 1))

export GUILE_REPL_ROOT GUILE_REPL_SLUG GUILE_REPL_DIR GUILE_REPL_PORT GUILE_REPL_PROXY_PORT

# Prefer guile3 where it exists: bare `guile' is 2.2.7 on some FreeBSD boxes
# and 3.x under Homebrew, and the tracing surfaces need 3.x.
if command -v guile3 >/dev/null 2>&1; then
    GUILE=${GUILE:-guile3}
else
    GUILE=${GUILE:-guile}
fi
export GUILE

# Run directly (not sourced) -> report.
case ${0##*/} in
    guile-repl-paths.sh)
        printf 'slug        %s\n' "$GUILE_REPL_SLUG"
        printf 'log dir     %s\n' "$GUILE_REPL_DIR"
        printf 'repl port   %s\n' "$GUILE_REPL_PORT"
        printf 'proxy port  %s  (repl port + 1)\n' "$GUILE_REPL_PROXY_PORT"
        printf 'guile       %s\n' "$(command -v "$GUILE" || echo 'NOT FOUND')"
        ;;
esac
