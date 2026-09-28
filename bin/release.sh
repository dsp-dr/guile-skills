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
[ -n "$GH" ] || { echo "release.sh: no \`gh\` with \`gh skill\` support found (needs gh >= the version that added it)" >&2; exit 2; }

gate() {
    echo "== regression tests: gmake test =="
    gmake test
    echo "== plugin manifest: claude plugin validate . =="
    claude plugin validate .
    echo "== skill validation: $GH skill publish --dry-run =="
    "$GH" skill publish --dry-run
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
        echo "== publishing $tag =="
        "$GH" skill publish --tag "$tag"
        ;;
    *)
        echo "usage: $0 {staging|production TAG}" >&2
        exit 2
        ;;
esac
