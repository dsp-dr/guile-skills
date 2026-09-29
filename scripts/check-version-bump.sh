#!/bin/sh
# check-version-bump.sh --- a change to what users receive needs a version bump.
#
#   scripts/check-version-bump.sh <base-ref>
#
# The directory serves whatever version plugin.json names, and `claude plugin
# update' tells a user "<name> is already at the latest version" when the file
# did not change. So shipping a skill edit without raising `version' leaves
# every existing install on the old copy, silently -- the failure this repo
# keeps finding in other forms.
#
# Compares the base ref against the WORKING TREE, not against HEAD. In CI the
# tree is clean so the two are identical; locally it means the check sees a bump
# you have edited but not yet committed, which is when you want to be told.
#
# Shipped means: what an install actually delivers. skills/** is copied by
# `gh skill install'; .claude-plugin/ is the manifest; scripts/lib/ is the
# canonical source of the files synced into each skill, so a change there
# reaches users through the copies. The rest are plugin-level component
# directories: a plugin install delivers the whole plugin root, so every one of
# them reaches users even though `gh skill install <skill>' does not copy them.
# monitors/ was missing from this list until 0.1.6 and agents/ until 0.2.0, and
# in both cases a change would have shipped with no version bump and no publish.
# Listing the directories a plugin can have is cheaper than rediscovering each.

set -u

BASE=${1:-}
[ -n "$BASE" ] || { echo "usage: $0 <base-ref>" >&2; exit 2; }
git rev-parse --verify --quiet "$BASE" >/dev/null || {
    echo "check-version-bump: cannot resolve base ref '$BASE'" >&2; exit 2; }

SHIPPED="skills/ .claude-plugin/ scripts/lib/ monitors/ agents/ commands/ hooks/ \
         output-styles/ themes/ workflows/ evals/ assets/ .lsp.json .mcp.json"

# `git diff' cannot see a file that is not tracked yet, so an entirely NEW shipped
# component -- a new skill directory, a new agent, a new monitor -- was invisible
# here until it was staged. In CI the tree is clean and it never mattered; locally
# it defeated the whole point, which is to warn before the commit. Measured
# 2026-09-29 with agents/geiser-setup.md: reported nothing until `git add'.
# So ask about untracked-but-not-ignored paths too.
#
# shellcheck disable=SC2086
changed=$(
    {
        git diff --name-only "$BASE" -- $SHIPPED
        git ls-files --others --exclude-standard -- $SHIPPED
    } | sort -u
)

if [ -z "$changed" ]; then
    echo "no shipped files changed since $BASE; no version bump needed."
    exit 0
fi

echo "shipped files changed since $BASE:"
printf '%s\n' "$changed" | sed 's/^/  /'
echo

if git diff "$BASE" -- .claude-plugin/plugin.json |
   grep -qE '^\+[[:space:]]*"version"[[:space:]]*:'; then
    echo "version was raised: $(grep '"version"' .claude-plugin/plugin.json | tr -d ' ,')"
    exit 0
fi

cat >&2 <<MSG
check-version-bump: shipped files changed but "version" in
.claude-plugin/plugin.json did not.

  Raise it, or an existing install stays on the old copy with no error:
  \`claude plugin update' reports "already at the latest version".

  RELEASING.org has the patch/minor/major table.
MSG
exit 1
