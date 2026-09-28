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

# Data root, in precedence order.
#
# ${CLAUDE_PLUGIN_DATA} -- ~/.claude/plugins/data/<id>/, created on first
# reference and kept across plugin updates -- is the sanctioned home for a
# plugin's persistent state, so it is what this uses. The catch is that it does
# NOT reach the Bash tool's environment: Claude Code substitutes it into skill
# Markdown only. So SKILL.md hands it over explicitly:
#
#     GUILE_SKILL_DATA="${CLAUDE_PLUGIN_DATA}" guile-repl-server.sh
#
# ~/.guile-skill is DEPRECATED and remains only as the fallback, so an existing
# checkout keeps working and keeps finding its old transcripts.
if [ -n "${GUILE_REPL_ROOT:-}" ]; then
    :                                            # explicit override wins
elif [ -n "${GUILE_SKILL_DATA:-}" ]; then
    GUILE_REPL_ROOT=$GUILE_SKILL_DATA
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    GUILE_REPL_ROOT=$CLAUDE_PLUGIN_DATA
else
    GUILE_REPL_ROOT=$HOME/.guile-skill
    GUILE_REPL_ROOT_IS_LEGACY=1
fi
GUILE_REPL_ROOT_IS_LEGACY=${GUILE_REPL_ROOT_IS_LEGACY:-0}
GUILE_REPL_SLUG=$(pwd | tr '/.' '--')
GUILE_REPL_DIR="$GUILE_REPL_ROOT/projects/$GUILE_REPL_SLUG"

# cksum is POSIX and present on FreeBSD, macOS and Linux; base 37000 keeps us
# in the IANA dynamic range and clear of the usual development ports.
GUILE_REPL_PORT=${GUILE_REPL_PORT:-$((37000 + $(printf '%s' "$GUILE_REPL_SLUG" | cksum | cut -d' ' -f1) % 900))}
GUILE_REPL_PROXY_PORT=$((GUILE_REPL_PORT + 1))

export GUILE_REPL_ROOT GUILE_REPL_ROOT_IS_LEGACY GUILE_REPL_SLUG GUILE_REPL_DIR \
       GUILE_REPL_PORT GUILE_REPL_PROXY_PORT

# Prefer an explicitly-3.x binary: bare `guile' is 2.2.7 on some FreeBSD boxes
# and 3.x under Homebrew, and the tracing surfaces need 3.x. FreeBSD ports name
# it guile3 and guile-3.0; Debian and Ubuntu name it guile-3.0 only, which is
# what CI runners have -- probing in this order covers all three.
if [ -z "${GUILE:-}" ]; then
    for guile_candidate in guile3 guile-3.0 guile; do
        if command -v "$guile_candidate" >/dev/null 2>&1; then
            GUILE=$guile_candidate
            break
        fi
    done
    GUILE=${GUILE:-guile}
fi
export GUILE

# Run directly (not sourced) -> report.
case ${0##*/} in
    guile-repl-paths.sh)
        printf 'data root   %s%s\n' "$GUILE_REPL_ROOT" \
            "$([ "$GUILE_REPL_ROOT_IS_LEGACY" = 1 ] && printf '  (DEPRECATED ~/.guile-skill; pass GUILE_SKILL_DATA=\044{CLAUDE_PLUGIN_DATA})')"
        printf 'slug        %s\n' "$GUILE_REPL_SLUG"
        printf 'log dir     %s\n' "$GUILE_REPL_DIR"
        printf 'repl port   %s\n' "$GUILE_REPL_PORT"
        printf 'proxy port  %s  (repl port + 1)\n' "$GUILE_REPL_PROXY_PORT"
        printf 'guile       %s\n' "$(command -v "$GUILE" || echo 'NOT FOUND')"
        ;;
esac
