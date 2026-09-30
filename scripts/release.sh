#!/bin/sh
# release.sh --- gate a release of this plugin behind its regression suite.
#
#   ./scripts/release.sh staging            # regression tests + validation, no publish
#   ./scripts/release.sh production TAG     # same gate, then a real `gh skill publish --tag TAG`
#   ./scripts/release.sh status TAG         # none | done | resume | conflict, and why
#
# `production' is idempotent: run it again at any point and it finishes what is
# missing or does nothing. A publish is two artifacts, the tag and the release
# `gh skill publish' creates from it, and either can exist without the other
# after a failure halfway through:
#
#   none      no tag                      -> gate, then gh skill publish --tag
#   done      tag at HEAD, release exists -> nothing; exit 0
#   resume    tag at HEAD, no release     -> gate, then gh release create from
#                                            the existing tag
#   conflict  tag on another commit       -> exit 1: a bump that did not happen
#
# After publishing it re-reads the state and fails unless it is `done', so a
# publish that reports success without leaving a release is loud, not silent.
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

# `gh skill` is a preview command that landed in gh v2.90.0. Pick whichever gh
# actually answers `gh skill --help' rather than trusting a version number:
# the packaged gh may lag (FreeBSD ports had 2.83.2 well after v2.101.0 shipped),
# so a go-installed ~/go/bin/gh is the usual second candidate. See CONTRIBUTING.org.
GH=${GH:-}
if [ -z "$GH" ]; then
    for candidate in gh "$HOME/go/bin/gh"; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" skill --help >/dev/null 2>&1; then
            GH=$candidate
            break
        fi
    done
fi
# If no candidate has it, staging runs the gate steps that exist and says plainly
# which one it could not run; production still refuses, because there is nothing
# to publish with. That is a tooling gap on this machine, not a failed gate.
SKILL_CMD=1
if [ -z "$GH" ]; then
    SKILL_CMD=0
    GH=gh
fi

# GNU make is `gmake' on FreeBSD and `make' on Linux, where `make' IS GNU make.
# CI runs on ubuntu, so probing matters: without it the gate dies at the first
# step with "gmake: not found" and the publish never happens.
MAKE=${MAKE:-$(command -v gmake || command -v make)}
[ -n "$MAKE" ] || { echo "release.sh: no make on PATH" >&2; exit 2; }

gate() {
    # The whole of `checks', not a hand-copied subset of it. This gate ran three
    # of eleven targets until 0.4.0 -- the same mistake 6143228 fixed in CI -- so
    # a drifted skill copy, a stale version or bad frontmatter could publish.
    # check-contracts is included, which is why gate.yml and publish.yml install
    # the CLI contracts/cell.json pins rather than latest.
    echo "== full check suite: $MAKE checks =="
    "$MAKE" checks
    if [ "$SKILL_CMD" -eq 1 ]; then
        echo "== skill validation: $GH skill publish --dry-run =="
        "$GH" skill publish --dry-run
    else
        echo "== skill validation: SKIPPED, this gh has no \`gh skill\` =="
        echo "   the other gate steps ran; nothing was published"
    fi
    echo "== gate passed =="
}

# publish_state TAG -> prints one of none | done | resume | conflict <sha>.
# Tags are fetched here, not trusted from checkout: a run queued behind another
# publish must see the tag that run created. The tag is peeled with ^{commit},
# so an annotated tag compares as its commit.
publish_state() {
    git fetch --quiet --force --tags origin 2>/dev/null || true
    at=$(git rev-parse --verify --quiet "refs/tags/$1^{commit}" 2>/dev/null) || at=''
    if [ -z "$at" ]; then
        echo none
    elif [ "$at" != "$(git rev-parse HEAD)" ]; then
        echo "conflict $at"
    elif "$GH" release view "$1" >/dev/null 2>&1; then
        echo done
    else
        echo resume
    fi
}

case ${1:-} in
    status)
        tag=${2:-}
        [ -n "$tag" ] || { echo "release.sh: status needs a tag" >&2; exit 2; }
        publish_state "$tag"
        ;;
    staging)
        gate
        ;;
    production)
        tag=${2:-}
        [ -n "$tag" ] || { echo "release.sh: production needs a tag, e.g. ./scripts/release.sh production v0.1.0" >&2; exit 2; }
        state=$(publish_state "$tag")
        case $state in
            done)
                echo "== $tag is already published at this commit; nothing to do =="
                exit 0 ;;
            conflict*)
                echo "release.sh: $tag already exists at ${state#conflict }, not at HEAD." >&2
                echo "  Raise version in .claude-plugin/plugin.json." >&2
                exit 1 ;;
        esac
        gate
        case $state in
            none)
                [ "$SKILL_CMD" -eq 1 ] || {
                    echo "release.sh: cannot publish -- no \`gh\` on PATH has \`gh skill\`." >&2
                    echo "  The gate above passed; publishing is the only blocked step." >&2
                    exit 2
                }
                echo "== publishing $tag =="
                "$GH" skill publish --tag "$tag" ;;
            resume)
                # The tag exists at HEAD but its release does not: an earlier run
                # stopped between the two. Finish it from the existing tag rather
                # than asking gh skill publish to create a tag that is already there.
                echo "== resuming $tag: tag exists at HEAD, creating its release =="
                "$GH" release create "$tag" --verify-tag --generate-notes --title "$tag" ;;
        esac
        after=$(publish_state "$tag")
        [ "$after" = done ] || {
            echo "release.sh: publish of $tag reported success, but the state is now '$after', not 'done'." >&2
            exit 1
        }
        echo "== $tag published and verified: tag at HEAD, release present =="
        ;;
    *)
        echo "usage: $0 {staging|production TAG|status TAG}" >&2
        exit 2
        ;;
esac
