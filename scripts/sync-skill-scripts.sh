#!/bin/sh
# sync-skill-scripts.sh --- copy shared scripts into each skill that needs them.
#
#   scripts/sync-skill-scripts.sh          # write the copies
#   scripts/sync-skill-scripts.sh --check  # fail if a copy has drifted
#
# Why copies rather than one shared directory: `gh skill install' copies
# skills/<name>/** and nothing else, so a skill installed on its own must carry
# everything it runs. A skill that reaches outside its own folder works from a
# checkout and breaks for everyone who installs it -- which is exactly the bug
# this layout replaced.
#
# scripts/lib/ holds the canonical copy and is not shipped. Edit there; the
# copies under skills/*/scripts/ are generated, and `gmake checks' fails when
# they drift.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# <shared file>:<skill that needs it>
# guile-repl-server.sh spawns the proxy, so the server skill carries it too.
# emacs-setup derives the same ports and load path the REPL uses, so it
# carries the path script and the layout detector.
PAIRS='guile-repl-paths.sh:repl-server
guile-repl-paths.sh:repl-eval
guile-repl-paths.sh:repl-proxy
guile-repl-proxy.scm:repl-server
guile-repl-proxy.scm:repl-proxy
guile-repl-paths.sh:emacs-setup
guile-project-detect.sh:emacs-setup'

drift=0
echo "$PAIRS" | while IFS=: read -r file skill; do
    src="$ROOT/scripts/lib/$file"
    dst="$ROOT/skills/$skill/scripts/$file"
    [ -f "$src" ] || { echo "sync-skill-scripts: missing canonical $src" >&2; exit 1; }
    if [ "$CHECK" -eq 1 ]; then
        if [ ! -f "$dst" ]; then
            echo "  MISSING  skills/$skill/scripts/$file" >&2
            drift=1
        elif ! cmp -s "$src" "$dst"; then
            echo "  DRIFTED  skills/$skill/scripts/$file (canonical: scripts/lib/$file)" >&2
            drift=1
        else
            echo "  ok       skills/$skill/scripts/$file"
        fi
        [ "$drift" -eq 0 ] || exit 1
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        chmod 755 "$dst"
        echo "  wrote    skills/$skill/scripts/$file"
    fi
done || exit 1

if [ "$CHECK" -eq 1 ]; then
    echo "shared scripts in sync."
else
    echo "shared scripts synced from scripts/lib/."
fi
