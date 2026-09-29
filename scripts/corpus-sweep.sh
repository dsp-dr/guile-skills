#!/bin/sh
# corpus-sweep.sh --- can this plugin actually serve every Guile project here?
#
#   ./scripts/corpus-sweep.sh            every Guile checkout under $(ghq root)
#   ./scripts/corpus-sweep.sh DIR...     just these
#
# Read-only. Starts no REPL, binds no port, writes nothing outside stdout. The
# question is readiness, and readiness is answerable by looking.
#
# Per project it reports what the plugin would derive and what Emacs would need:
#
#   MODULES  where (define-module ...) forms actually live -- NOT assumed to be src/
#   PORT     37000 + cksum(slug) mod 900, and the proxy at +1
#   DIRLOC   a .dir-locals.el, and whether it PINS the interpreter (the trap)
#   TESTS    a test directory, and whether SRFI-64 is used
#   GEISER   whether geiser-connect could work: needs a 3.x binary and a load path
#
# A project with no modules is not broken -- it is scripts, and it says so.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DETECT="$ROOT/scripts/guile-project-detect.sh"
PATHS=""
for c in "$ROOT/scripts/lib/guile-repl-paths.sh" \
         "$ROOT/skills/repl-server/scripts/guile-repl-paths.sh"; do
    [ -r "$c" ] && PATHS=$c && break
done

if [ $# -gt 0 ]; then
    targets=$*
else
    R=$(ghq root 2>/dev/null || echo "$HOME/ghq")
    targets=$(find "$R" -maxdepth 4 -type d -name '.git' 2>/dev/null |
              sed 's|/\.git$||' | sort |
              while read -r d; do
                  find "$d" -name '*.scm' -not -path '*/.git/*' 2>/dev/null |
                      head -1 | grep -q . && echo "$d"
              done)
fi

printf '%-34s %-22s %-13s %-22s %-14s %s\n' PROJECT MODULES PORT DIRLOC TESTS GEISER
for d in $targets; do
    [ -d "$d" ] || continue
    name=$(basename "$d")

    mods=$( (cd "$d" && sh "$DETECT" 2>/dev/null) | sed -n 's/^module dirs  *//p')
    case $mods in ''|none*) mods='-- scripts' ;; esac

    port=$( (cd "$d" && [ -n "$PATHS" ] && sh "$PATHS" 2>/dev/null) |
            sed -n 's/^repl port  *//p')
    [ -n "$port" ] && port="$port/$((port + 1))" || port='?'

    if [ -f "$d/.dir-locals.el" ]; then
        if grep -q 'geiser-guile-binary' "$d/.dir-locals.el" 2>/dev/null; then
            dirloc='yes PINS BINARY'
        else
            dirloc='yes'
        fi
    else
        dirloc='no'
    fi

    tests='no'
    for t in tests test t; do [ -d "$d/$t" ] && tests="$t/" && break; done
    if [ "$tests" != no ] && grep -rqs 'srfi.64\|test-begin' "$d/$tests" 2>/dev/null; then
        tests="$tests srfi64"
    fi

    # geiser-connect needs a 3.x interpreter and somewhere to load from
    guile=$( (cd "$d" && sh "$DETECT" 2>/dev/null) | sed -n 's/^guile  *//p')
    case "$guile:$mods" in
        'NOT FOUND'*) geiser='no guile' ;;
        *:--\ scripts) geiser='no load path' ;;
        *)            geiser='ready' ;;
    esac

    printf '%-34s %-22s %-13s %-22s %-14s %s\n' \
        "$name" "$(echo "$mods" | cut -c1-22)" "$port" "$dirloc" "$tests" "$geiser"
done
