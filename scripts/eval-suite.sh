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
# Two gates, in this order, because they fail differently:
#
#   1. VERSION. plugin eval shipped in 2.1.269
#      (https://code.claude.com/docs/en/whats-new/2026-w37). Below that the
#      subcommand may not exist, or may exist and refuse.
#
#   2. THE PROBE. Version is necessary, not sufficient: on 2.1.261 the subcommand
#      exists, `--help' prints the COMPLETE usage, and the run still answers
#      "`plugin eval` is currently in early access". The harness is compiled in and
#      gated elsewhere -- account-side or channel-side, not established which. So a
#      version check alone would promise a run that does not happen.
#
#      The probe is free: the gate answers before any model call. That is a property
#      of where the gate sits, not a guarantee anyone made, so the probe is still
#      run with a cost ceiling.
#
# Only after both pass does anything expensive start.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 2

# The release that ships it. Bump this only with a changelog entry to cite.
MIN_VERSION=2.1.269
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
[ -n "$have" ] || { echo "eval-suite: could not read the CLI version" >&2; exit 2; }

# sort -V puts the lower first; if MIN sorts first, we are at or above it.
lowest=$(printf '%s\n%s\n' "$have" "$MIN_VERSION" | sort -V | head -1)
if [ "$have" != "$MIN_VERSION" ] && [ "$lowest" = "$have" ]; then
    echo "eval-suite: claude $have is below $MIN_VERSION, where plugin eval shipped."
    echo "eval-suite: nothing was run and nothing was spent."
    echo "eval-suite: probing anyway, because the gate may be account-side:"
else
    echo "eval-suite: claude $have >= $MIN_VERSION"
fi

# --- gate 2: the free probe ------------------------------------------------
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
