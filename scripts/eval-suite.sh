#!/bin/sh
# eval-suite.sh --- run `claude plugin eval' once the CLI is new enough, and not before.
#
#   ./scripts/eval-suite.sh              probe, then run the suite if it is available
#   ./scripts/eval-suite.sh --probe      probe only; never spends anything
#   ./scripts/eval-suite.sh --case NAME  one case (implies bounded defaults)
#
# Exit 0 = ran, or correctly declined to run. 1 = a case scored below the
# threshold. 2 = could not run at all.
#
# MANUAL. Not in `checks' and not in any workflow: a full suite is real model calls
# on your account. See `gmake audit' for the same reasoning at more length.
#
# Two gates, in this order, and BOTH ARE BEHAVIOURAL. There is deliberately no
# minimum-version constant:
#
#   1. DOES THE SUBCOMMAND EXIST?  `claude plugin eval --help' exits non-zero on a
#      build that has no such subcommand. Asking directly never goes stale.
#
#   2. DOES A RUN GET PAST THE GATE?  On 2.1.261 the subcommand exists, --help
#      prints the COMPLETE usage, and the run still answers "`plugin eval` is
#      currently in early access". So existence is not permission, and only a run
#      settles it. The probe is free -- the gate answers before any model call --
#      which is a property of where the gate sits rather than a guarantee anyone
#      made, so it still runs under a ceiling.
#
# An earlier version of this script pinned MIN_VERSION=2.1.269 from the changelog.
# That was wrong twice over: 2.1.268 was observed running it, so the constant was
# off by a release; and the same build that refuses (2.1.261) prints full help, so
# a version test would have been answering a different question anyway. A constant
# read off a changelog is a claim about the world that ages; `--help' and a probe
# are questions put to the binary in front of you.
#
# Only after both pass does anything expensive start.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 2

PROBE_CASE=${PROBE_CASE:-no-linter-claim}
PROBE_CEILING=${PROBE_CEILING:-0.01}
SUITE_CEILING=${SUITE_CEILING:-5.00}
RUNS=${RUNS:-3}
THRESHOLD=${THRESHOLD:-0.8}

mode=run
case ${1:-} in
    --probe) mode=probe ;;
    --case)  PROBE_CASE=${2:?--case needs a name}; mode=one ;;
esac

command -v claude >/dev/null 2>&1 || { echo "eval-suite: no claude on PATH" >&2; exit 2; }

have=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "eval-suite: claude ${have:-unknown}"

# --- gate 1: does the subcommand exist on this build? ----------------------
if ! claude plugin eval --help >/dev/null 2>&1; then
    echo "eval-suite: this build has no \`plugin eval\` subcommand."
    echo "eval-suite: nothing was run and nothing was spent."
    exit 0
fi

# --- gate 2: the free probe, which is the one that decides -----------------
probe=$(claude plugin eval . --case "$PROBE_CASE" --runs 1 \
            --max-cost-usd "$PROBE_CEILING" --no-publish 2>&1)
probe_status=$?

if printf '%s' "$probe" | grep -q 'currently in early access'; then
    echo "eval-suite: gated -- \`plugin eval\` is currently in early access."
    echo "eval-suite: \$0 spent. Re-run after upgrading; see issue #20."
    exit 0
fi

if [ "$mode" = probe ]; then
    echo "eval-suite: probe returned (status $probe_status):"
    printf '%s\n' "$probe" | tail -20
    exit 0
fi

# The probe already ran one case. If that is all that was asked, report it.
if [ "$mode" = one ]; then
    printf '%s\n' "$probe"
    exit "$probe_status"
fi

# --- the suite -------------------------------------------------------------
echo "eval-suite: gate is open; running the full suite."
echo "eval-suite: $RUNS run(s) per case, with/without arms, ceiling \$$SUITE_CEILING."
claude plugin eval . \
    --runs "$RUNS" \
    --threshold "$THRESHOLD" \
    --max-cost-usd "$SUITE_CEILING" \
    --no-publish
