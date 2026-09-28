#!/bin/sh
# ship-check.sh --- what does a user actually receive, and does it work?
#
# `gh skill install' copies skills/<name>/** and nothing else, and it strips the
# executable bit on the way. So two things can go wrong silently:
#
#   1. a SKILL.md names a script that is not inside its own skill folder, so the
#      script never ships and every documented command fails for an installed
#      user while working perfectly in a checkout;
#   2. a SKILL.md invokes a shipped script directly, which fails because the
#      installed copy is not executable.
#
# This installs into a throwaway directory and checks both.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

GH=""
for c in gh "$HOME/go/bin/gh"; do
    command -v "$c" >/dev/null 2>&1 && "$c" skill --help >/dev/null 2>&1 && { GH=$c; break; }
done
[ -n "$GH" ] || { echo "ship-check: needs a gh with \`gh skill\` (>= 2.90.0); see CONTRIBUTING.org" >&2; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

"$GH" skill install "$ROOT" --from-local --agent claude-code --dir "$tmp" --all >/dev/null 2>&1 ||
    { echo "ship-check: install failed" >&2; exit 1; }

echo "files an install delivers:"
(cd "$tmp" && find . -type f | sed 's|^\./|  |' | sort)
echo

problems=0
for skill_md in "$tmp"/*/SKILL.md; do
    skill=$(basename "$(dirname "$skill_md")")

    # every ${CLAUDE_SKILL_DIR}/scripts/<file> the skill names must have shipped
    grep -o '${CLAUDE_SKILL_DIR}/scripts/[A-Za-z0-9_.-]*' "$skill_md" 2>/dev/null |
    sed 's|.*/||' | sort -u | while read -r f; do
        [ -n "$f" ] || continue
        if [ -f "$tmp/$skill/scripts/$f" ]; then
            printf '  ok       %s names %s, and it shipped\n' "$skill" "$f"
        else
            printf '  MISSING  %s names %s, which did NOT ship\n' "$skill" "$f" >&2
            echo x >> "$tmp/.problems"
        fi
    done

    # and must be invoked through an interpreter, because +x is stripped
    if grep -nE '(^|[^a-z])\$\{CLAUDE_SKILL_DIR\}/scripts/' "$skill_md" 2>/dev/null |
       grep -vE '(sh|bash|guile[0-9.-]*|python3?|perl) \$\{CLAUDE_SKILL_DIR\}' >/dev/null; then
        printf '  DIRECT   %s invokes a script without an interpreter; installed copies are not executable\n' "$skill" >&2
        echo x >> "$tmp/.problems"
    fi
done

[ -f "$tmp/.problems" ] && problems=$(wc -l < "$tmp/.problems" | tr -d ' ')
echo
if [ "${problems:-0}" -gt 0 ]; then
    echo "ship-check: $problems problem(s) -- an installed user cannot run what the skills document." >&2
    exit 1
fi
echo "ship-check: every script a SKILL.md names ships with its skill and is invoked through an interpreter."
