#!/bin/sh
# wip.sh --- is anything being held back?
#
# One report over every worktree of this repository, answering the only question
# that matters at the end of a session: is there work that exists nowhere but
# this machine?
#
# Five ways to hold onto something, and all five are silent:
#
#   1. uncommitted changes in a working tree
#   2. a commit that was never pushed
#   3. a git note that was never pushed -- refs/notes/commits is not carried by
#      `git push', `--all' or `--follow-tags'
#   4. a note stranded on a pre-rebase sha, because notes.rewriteRef was unset
#   5. a commit whose content does not match what its message claims, which is
#      what happens when files are staged one at a time and one is forgotten
#
# (5) cannot be checked mechanically, so this prints each commit's file list and
# leaves the reading to you. It is the failure that actually happened here on
# 2026-09-29: a commit announcing a version bump that did not contain it.

set -u

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)" || exit 1
held=0

printf '\033[1m== worktrees\033[0m\n'
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
    b=$(git -C "$wt" branch --show-current 2>/dev/null)
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | grep -cv '^?? ')
    untracked=$(git -C "$wt" status --porcelain 2>/dev/null | grep -c '^?? ')
    printf '  %-56s %-38s dirty=%s untracked=%s\n' "$wt" "${b:-<detached>}" "$dirty" "$untracked"
    if [ "$dirty" -gt 0 ]; then
        git -C "$wt" status --short 2>/dev/null | grep -v '^?? ' | sed 's/^/      /'
    fi
done

printf '\n\033[1m== branches not pushed, or ahead of their remote\033[0m\n'
any=0
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    up=$(git rev-parse --abbrev-ref --symbolic-full-name "$b@{u}" 2>/dev/null) || {
        printf '  %-44s NO UPSTREAM (exists only here)\n' "$b"; any=1; continue; }
    ahead=$(git rev-list --count "$up..$b" 2>/dev/null || echo '?')
    behind=$(git rev-list --count "$b..$up" 2>/dev/null || echo '?')
    if [ "$ahead" != "0" ]; then
        printf '  %-44s ahead %s / behind %s of %s\n' "$b" "$ahead" "$behind" "$up"; any=1
    fi
done
[ "$any" = 0 ] && printf '  every branch is pushed and not ahead\n' || held=1

printf '\n\033[1m== git notes\033[0m\n'
local_notes=$(git rev-parse --quiet --verify refs/notes/commits || echo '')
remote_notes=$(git ls-remote origin refs/notes/commits 2>/dev/null | cut -f1)
if [ -z "$local_notes" ]; then
    printf '  no local notes ref\n'
elif [ "$local_notes" = "$remote_notes" ]; then
    printf '  in sync with origin (%s)\n' "$(git notes list | wc -l | tr -d ' ') notes"
else
    printf '  LOCAL AHEAD: push with  git push origin refs/notes/commits\n'
    printf '    local  %s\n    remote %s\n' "$local_notes" "${remote_notes:-<none>}"
    held=1
fi
for cfg in notes.rewriteRef notes.rewrite.rebase notes.rewrite.amend; do
    v=$(git config --get "$cfg" 2>/dev/null)
    [ -n "$v" ] || { printf '  %s is UNSET -- a rebase will strand notes\n' "$cfg"; held=1; }
done

printf '\n\033[1m== commits on this branch not on main, and what they contain\033[0m\n'
base=$(git rev-parse --verify --quiet origin/main || git rev-parse --verify --quiet main)
if [ -n "$base" ]; then
    for c in $(git rev-list "$base..HEAD" 2>/dev/null); do
        printf '  %s %s\n' "$(git log -1 --format='%h' "$c")" "$(git log -1 --format='%s' "$c")"
        git show --stat --format='' "$c" | sed '/^$/d;s/^/      /'
        git notes show "$c" >/dev/null 2>&1 || printf '      NO NOTE on this commit\n'
    done
else
    printf '  cannot resolve a base to compare against\n'
fi

printf '\n\033[1m== open pull requests\033[0m\n'
if command -v gh >/dev/null 2>&1; then
    gh pr list --state open --json number,headRefName,baseRefName,labels \
      --jq '.[] | "  #\(.number) \(.headRefName) -> \(.baseRefName)  [\(.labels|map(.name)|join(","))]"' \
      2>/dev/null || printf '  (gh could not list; not fatal)\n'
else
    printf '  gh not on PATH\n'
fi

printf '\n'
if [ "$held" = 0 ]; then
    printf '\033[1mnothing is being held back.\033[0m\n'
else
    printf '\033[1msomething is held only on this machine -- see above.\033[0m\n'
fi
exit 0
