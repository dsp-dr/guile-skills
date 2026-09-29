#!/bin/sh
# dx-harness.sh --- re-run the metadata checks whenever a watched file changes.
#
# The `harness' window of scripts/dx.sh. Watches the plugin's own metadata -- the
# manifest, every SKILL.md, every evals.json, monitors.json, the agents -- and
# re-runs whichever validators exist in this checkout.
#
# Which validators exist varies by branch, so it discovers them instead of naming
# them: the same reason gate.yml iterates over tests/validate-*.py rather than
# calling make targets that may not be defined yet.
#
# Polling, not inotify: FreeBSD has no inotify, and a 2-second stat of a few dozen
# files costs nothing next to being portable.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1
INTERVAL=${DX_INTERVAL:-2}

watched() {
    {
        echo .claude-plugin/plugin.json
        ls skills/*/SKILL.md 2>/dev/null
        ls skills/*/evals/evals.json 2>/dev/null
        ls monitors/monitors.json 2>/dev/null
        ls agents/*.md 2>/dev/null
        ls tests/validate-*.py 2>/dev/null
    } 2>/dev/null
}

fingerprint() {
    # mtimes only: content hashing every file each tick is the wrong trade, and a
    # touch with no edit costing one extra run is harmless.
    for f in $(watched); do
        [ -e "$f" ] && printf '%s:%s\n' "$f" "$(
            stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null
        )"
    done | cksum
}

run_validators() {
    found=0
    for v in tests/validate-frontmatter.py tests/validate-evals.py tests/validate-monitors.py; do
        [ -f "$v" ] || continue
        found=$((found + 1))
        printf '\n== %s\n' "$v"
        python3 "$v" 2>&1 | sed 's/^/   /'
    done
    if command -v claude >/dev/null 2>&1; then
        printf '\n== claude plugin validate --strict\n'
        claude plugin validate . --strict 2>&1 | sed 's/^/   /' | tail -6
    fi
    [ "$found" -gt 0 ] || printf '\n(no tests/validate-*.py in this checkout)\n'
}

printf 'dx-harness: watching %s file(s), every %ss.  Ctrl-C to stop.\n' \
    "$(watched | wc -l | tr -d ' ')" "$INTERVAL"

last=''
while :; do
    now=$(fingerprint)
    if [ "$now" != "$last" ]; then
        printf '\n\033[1m--- %s ---\033[0m\n' "$(date '+%H:%M:%S')"
        run_validators
        last=$now
    fi
    sleep "$INTERVAL"
done
