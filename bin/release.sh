#!/bin/sh
# release.sh --- gate a release of this plugin behind its regression suite.
#
#   ./bin/release.sh staging            # regression tests + validation, no publish
#   ./bin/release.sh production TAG     # same gate, then a real `gh skill publish --tag TAG`
#
# This plugin has no running service, so "staging" and "production" don't mean
# separate deployed environments -- they mean the same gate run twice: once as
# a dry run, once for real. `gh skill publish` already draws that exact line
# with --dry-run vs --tag, so this script is a thin wrapper around it plus the
# repo's own regression tests, not a second release mechanism.
#
# release:start / release:end / release:skip labels on the tracking PR or
# issue are for humans following a release along -- this script does not read
# or set them itself.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# `gh skill` is a preview command; pick whichever gh on PATH actually has it,
# falling back to a go-installed one ahead of an older packaged gh.
GH=${GH:-}
if [ -z "$GH" ]; then
    for candidate in gh "$HOME/go/bin/gh"; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" skill --help >/dev/null 2>&1; then
            GH=$candidate
            break
        fi
    done
fi
# `gh skill` ships in no released gh as of 2026-09-28 -- not as a builtin and not
# as an extension. Staging therefore runs the gate steps that exist and says
# plainly which one it could not run; production still refuses, because there is
# nothing to publish with.
SKILL_CMD=1
if [ -z "$GH" ]; then
    SKILL_CMD=0
    GH=gh
fi

gate() {
    echo "== regression tests: gmake test =="
    gmake test
    echo "== plugin manifest: claude plugin validate . =="
    claude plugin validate .
    echo "== eval suites: gmake check-evals =="
    gmake check-evals
    if [ "$SKILL_CMD" -eq 1 ]; then
        echo "== skill validation: $GH skill publish --dry-run =="
        "$GH" skill publish --dry-run
    else
        echo "== skill validation: SKIPPED, this gh has no \`gh skill\` =="
        echo "   the other gate steps ran; nothing was published"
    fi
    echo "== gate passed =="
}

case ${1:-} in
    staging)
        gate
        ;;
    production)
        tag=${2:-}
        [ -n "$tag" ] || { echo "release.sh: production needs a tag, e.g. ./bin/release.sh production v0.1.0" >&2; exit 2; }
        gate
        [ "$SKILL_CMD" -eq 1 ] || {
            echo "release.sh: cannot publish -- no \`gh\` on PATH has \`gh skill\`." >&2
            echo "  The gate above passed; publishing is the only blocked step." >&2
            exit 2
        }
        echo "== publishing $tag =="
        "$GH" skill publish --tag "$tag"
        ;;
    *)
        echo "usage: $0 {staging|production TAG}" >&2
        exit 2
        ;;
esac
