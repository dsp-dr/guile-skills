#!/bin/sh
# guile-repl-health.sh --- what the `guile-repl-health' monitor tails.
#
# Started by Claude Code from monitors/monitors.json the first time the
# repl-server skill runs. Everything it prints reaches the agent as a
# notification.
#
# It tails the two stderr streams, NOT the transcript. That is the whole point:
#
#   repl.stderr / proxy.stderr are where a process that never started confesses.
#   8178314 is the case --- the proxy's interpreter name was wrong, so it never
#   ran, and because the harness redirected its stderr the symptom was an empty
#   transcript. A missing transcript reads as a logging bug rather than as a
#   process that died, and that misreading cost more than the bug.
#
#   repl.log is the transcript. It contains whatever was evaluated, by anyone
#   holding the socket --- including a human in Geiser who never asked for an
#   agent to read along. The agent already sees its own results through
#   repl-eval, so tailing it would duplicate what the agent knows and
#   surface what it has no business knowing. Not shipped on purpose. To watch it
#   anyway, add a second entry naming "$GUILE_REPL_DIR/repl.log" in your own
#   settings, with that trade-off in mind.
#
# Usage: guile-repl-health.sh [DATA_ROOT]
#
# DATA_ROOT is ${CLAUDE_PLUGIN_DATA}, handed over by monitors.json. It has to be
# passed rather than read from the environment: Claude Code substitutes that
# variable into plugin configuration and skill Markdown, and it does NOT reach a
# Bash environment (2dc20e9). If the substitution does not happen, the argument
# arrives as the literal text and is ignored, and guile-repl-paths.sh falls back
# through its usual precedence.

set -u

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || {
    echo "guile-repl-health: cannot resolve my own directory" >&2; exit 1; }
plugin_root=$(dirname "$here")

# The canonical copy lives in scripts/lib/; this is the copy that ships inside
# the skill, which is what a plugin install actually delivers (8d71a62).
paths=$plugin_root/skills/repl-server/scripts/guile-repl-paths.sh
[ -r "$paths" ] || {
    echo "guile-repl-health: $paths is missing; is the plugin fully installed?" >&2
    exit 1
}

case ${1:-} in
    '' | '${CLAUDE_PLUGIN_DATA}')
        : ;;                        # absent, or handed over unsubstituted
    *)
        GUILE_SKILL_DATA=$1
        export GUILE_SKILL_DATA ;;
esac

# shellcheck source=../scripts/lib/guile-repl-paths.sh
. "$paths"

mkdir -p "$GUILE_REPL_DIR" 2>/dev/null || true

printf 'guile-repl-health: watching %s\n' "$GUILE_REPL_DIR"
printf 'guile-repl-health: repl %s, proxy %s, guile %s\n' \
    "$GUILE_REPL_PORT" "$GUILE_REPL_PROXY_PORT" "$(command -v "$GUILE" || echo 'NOT FOUND')"
if [ "$GUILE_REPL_ROOT_IS_LEGACY" = 1 ]; then
    printf 'guile-repl-health: data root is the DEPRECATED %s --- if the skill was\n' "$GUILE_REPL_ROOT"
    printf 'guile-repl-health: given GUILE_SKILL_DATA, these are not the files it writes.\n'
fi

# -F, not -f: the files do not exist until a REPL starts, and both are replaced
# on rotation. tail reports each by name, so a notification says which stream
# spoke.
exec tail -F "$GUILE_REPL_DIR/repl.stderr" "$GUILE_REPL_DIR/proxy.stderr"
