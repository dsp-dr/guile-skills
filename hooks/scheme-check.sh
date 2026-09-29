#!/bin/sh
# scheme-check.sh --- after an edit to a .scm file, is it still balanced?
#
# Run by hooks/hooks.json on PostToolUse for Write and Edit. Claude Code passes
# the tool's JSON on stdin; the file path is pulled out of it.
#
# It CHECKS and does not rewrite. Hand-editing delimiters is the most common
# anti-pattern in the corpus this plugin was designed from -- 22 of 75 reviewed
# skills warn about it -- and the failure is that an edit leaves a file unreadable
# while looking plausible. Detecting that immediately is the whole value.
#
# Reformatting on every write is a different and worse proposition: it produces
# diffs nobody asked for, it fights whatever the project already does, and on a
# file that is already unbalanced it cannot be correct. `gmake fmt' does that, when
# asked. This hook only tells you when you have broken something.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EL="$HERE/scheme-indent.el"

command -v emacs >/dev/null 2>&1 || exit 0   # no emacs, no opinion
[ -r "$EL" ] || exit 0

# Pull .scm paths out of the hook payload without requiring jq.
payload=$(cat 2>/dev/null || true)
files=$(printf '%s' "$payload" |
        tr ',{}' '\n\n\n' |
        sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        grep -E '\.scm$' || true)

[ -n "$files" ] || exit 0

out=$(emacs --batch -Q -l "$EL" -- --check $files 2>/dev/null)
status=$?

if [ "$status" -eq 3 ]; then
    printf 'Unbalanced Scheme after this edit:\n%s\n' "$out" >&2
    printf 'Nothing was rewritten. Fix the delimiters before evaluating anything:\n' >&2
    printf 'a REPL will report a confusing error far from the real cause.\n' >&2
    exit 2      # non-zero tells Claude Code the hook found a problem
fi
exit 0
