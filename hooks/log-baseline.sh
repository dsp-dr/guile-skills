#!/bin/sh
# log-baseline.sh --- mark where the logs were before this session touched them.
#
#   log-baseline.sh            record the baseline (SessionStart)
#   log-baseline.sh --since    print only what has been appended since it
#   log-baseline.sh --show     print the baseline itself
#
# Why this is needed, from the record rather than from theory:
#
#   repl.stderr is TRUNCATED on every start (`>' in guile-repl-server.sh) while
#   proxy.stderr APPENDS forever (`>>'). So one file loses the evidence of the
#   previous crash and the other accumulates every crash ever, and in both cases
#   "what did THIS run produce" is unanswerable by looking. 8178314 is the case
#   where that mattered: a proxy that never started, whose only evidence was in a
#   stderr file nobody could date.
#
# The baseline lives beside the logs in the plugin data directory, NOT in the
# project: the working tree never collects run artifacts, which is the same rule
# that keeps transcripts out of the repository. ${CLAUDE_PROJECT_DIR} identifies
# which project this is -- note the name: CLAUDE_PROJECT_DIR. CLAUDE_PROJECT_ROOT
# does not exist (checked against the CLI binary, 2026-09-29).

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ROOT=$(dirname "$HERE")
PROJECT=${CLAUDE_PROJECT_DIR:-$(pwd)}

cd "$PROJECT" 2>/dev/null || exit 0     # a hook must never fail a session

for c in "$PLUGIN_ROOT/scripts/lib/guile-repl-paths.sh" \
         "$PLUGIN_ROOT/skills/repl-server/scripts/guile-repl-paths.sh"; do
    if [ -r "$c" ]; then
        # shellcheck source=/dev/null
        . "$c"
        break
    fi
done
[ -n "${GUILE_REPL_DIR:-}" ] || exit 0

BASE="$GUILE_REPL_DIR/.baseline"
FILES="repl.log repl.stderr proxy.stderr"

size_of() {
    [ -f "$1" ] || { printf '0'; return; }
    wc -c < "$1" | tr -d ' '
}

case ${1:-} in
    --show)
        [ -r "$BASE" ] && cat "$BASE" || echo "no baseline recorded"
        ;;
    --since)
        [ -r "$BASE" ] || { echo "no baseline for this project; nothing to compare"; exit 0; }
        for f in $FILES; do
            was=$(sed -n "s/^$f  *//p" "$BASE")
            was=${was:-0}
            now=$(size_of "$GUILE_REPL_DIR/$f")
            if [ "$now" -gt "$was" ]; then
                printf '\n== %s  (+%s bytes since baseline)\n' "$f" "$((now - was))"
                dd if="$GUILE_REPL_DIR/$f" bs=1 skip="$was" 2>/dev/null
            elif [ "$now" -lt "$was" ]; then
                # repl.stderr is truncated on every start, so smaller means restarted.
                printf '\n== %s  TRUNCATED since baseline (was %s, now %s) -- the REPL restarted\n' \
                    "$f" "$was" "$now"
                cat "$GUILE_REPL_DIR/$f" 2>/dev/null
            fi
        done
        ;;
    *)
        mkdir -p "$GUILE_REPL_DIR" 2>/dev/null || exit 0
        {
            printf '# baseline for %s\n' "$PROJECT"
            printf '# recorded %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            printf 'guile %s\n' "$(command -v "${GUILE:-guile}" 2>/dev/null || echo none)"
            printf 'guile-version %s\n' \
                "$("${GUILE:-guile}" --version 2>/dev/null | head -1 || echo unknown)"
            for f in $FILES; do
                printf '%s %s\n' "$f" "$(size_of "$GUILE_REPL_DIR/$f")"
            done
        } > "$BASE" 2>/dev/null || exit 0
        ;;
esac
exit 0
