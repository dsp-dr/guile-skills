#!/bin/sh
# audit.sh --- a model-graded audit of this plugin, reduced to one bit.
#
#   ./scripts/audit.sh          audit the working tree
#   ./scripts/audit.sh --base main   audit only what this branch changed
#
# Exit 0 = PASS, 1 = FAIL, 2 = could not run (claude absent, no credentials).
#
# MANUAL ONLY. This is deliberately not in `checks' and must never enter a
# workflow:
#
#   - it costs tokens on every invocation, and `checks' is run on every save by
#     the dx harness;
#   - it is model-graded, so it is not reproducible the way the deterministic
#     validators are -- two runs can disagree, and a gate that disagrees with
#     itself teaches people to ignore it;
#   - CI has no credentials, so it would report 2 forever and be deleted.
#
# The deterministic checks stay authoritative. This one catches the class they
# cannot: conventions a human reviewer would notice and no schema encodes.
#
# It prefers plugin-dev's `plugin-validator' agent when that plugin is installed,
# because it is the official statement of what a well-formed plugin looks like.
# Without it, the same question is asked directly; the verdict contract is the same.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 2

BASE=""
[ "${1:-}" = "--base" ] && { BASE=${2:-main}; }

command -v claude >/dev/null 2>&1 || {
    echo "audit: the Claude Code CLI is not on PATH; skipping" >&2
    exit 2
}

scope="the whole working tree"
diff_hint=""
if [ -n "$BASE" ]; then
    scope="only the files this branch changed against $BASE"
    diff_hint="Changed files:
$(git diff --name-only "$BASE"... 2>/dev/null | sed 's/^/  /')
"
fi

# plugin-dev ships `plugin-validator'; use it when present.
agent_hint=""
if claude plugin list 2>/dev/null | grep -qi 'plugin-dev'; then
    agent_hint="Use the plugin-validator agent from plugin-dev for the structural half."
fi

prompt=$(cat <<PROMPT
Audit this Claude Code plugin for violations of the plugin, skill and marketplace
conventions. Review $scope.
$diff_hint
$agent_hint

Check at least: the manifest against the manifest reference; every SKILL.md
frontmatter and whether each description states both what it does and when to use
it; that shipped paths and the version gate agree; that hooks.json, monitors.json
and marketplace.json have the shapes the CLI requires; and that nothing shipped
references a path that does not exist.

This repository already runs deterministic checks for eval suites, monitor
entries, skill frontmatter, contract drift and Scheme balance. Do not re-report
what \`gmake checks\` already enforces. Report only what a reviewer would catch
and a schema would not.

Be concise. List findings as one line each, most severe first, with a file:line.
Then print a final line that is EXACTLY one word: PASS if you found nothing that
should block a release, or FAIL if you did. Nothing after that word.
PROMPT
)

out=$(printf '%s' "$prompt" | claude -p \
        --allowed-tools Read Grep Glob \
        --permission-mode plan \
        2>/dev/null) || {
    echo "audit: claude could not run (credentials? network?)" >&2
    exit 2
}

printf '%s\n' "$out"

verdict=$(printf '%s' "$out" | tr -d '\r' | grep -oE '^(PASS|FAIL)$' | tail -1)
case $verdict in
    PASS) echo "audit: PASS" >&2; exit 0 ;;
    FAIL) echo "audit: FAIL" >&2; exit 1 ;;
    *)    echo "audit: no verdict line; treating as inconclusive" >&2; exit 2 ;;
esac
