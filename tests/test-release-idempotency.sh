#!/bin/sh
# test-release-idempotency.sh --- scripts/release.sh production must be safe to rerun.
#
# Every case runs against a throwaway origin and clone with a stub `gh' that
# records its calls, so nothing here reaches GitHub (docs/isolation.org). The
# gate is stubbed with MAKE=true: this suite tests the publish state machine,
# and `gmake checks' tests the gate.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0
failed=0
check() { if [ "$1" = yes ]; then passed=$((passed + 1)); printf '  ok    %s\n' "$2"
          else failed=$((failed + 1)); printf '  FAIL  %s\n' "$2"; fi; }

# The stub: releases are files under $STUB_STATE, calls are appended to
# $STUB_STATE/calls. STUB_PUBLISH=ok|tag-only|nothing selects how
# `gh skill publish --tag' behaves.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_STATE/calls"
case "$1 $2" in
    "skill --help")    exit 0 ;;
    "skill publish")
        [ "$3" = "--dry-run" ] && exit 0
        tag=$4
        case ${STUB_PUBLISH:-ok} in
            nothing)  exit 0 ;;                         # claims success, does nothing
            tag-only) git tag -a "$tag" -m "$tag" && git push -q origin "$tag"; exit 1 ;;
            ok)       git tag -a "$tag" -m "$tag" && git push -q origin "$tag" &&
                      touch "$STUB_STATE/release-$tag"; exit 0 ;;
        esac ;;
    "release view")    [ -f "$STUB_STATE/release-$3" ] ;;
    "release create")
        git rev-parse --verify --quiet "refs/tags/$3" >/dev/null || exit 1
        touch "$STUB_STATE/release-$3" ;;
    *) echo "stub gh: unexpected: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# fresh CASE -> a clone with two commits whose origin is a bare repo, and a copy
# of release.sh inside it, so release.sh's own ROOT is the clone.
fresh() {
    d="$WORK/$1"; mkdir -p "$d"
    git init -q --bare "$d/origin.git"
    git clone -q "$d/origin.git" "$d/repo" 2>/dev/null
    (cd "$d/repo" && git config user.email t@t && git config user.name t &&
     git commit -q --allow-empty -m one && git commit -q --allow-empty -m two &&
     git push -q origin HEAD 2>/dev/null)
    mkdir -p "$d/repo/scripts" "$d/state"
    cp "$ROOT/scripts/release.sh" "$d/repo/scripts/release.sh"
    printf '%s' "$d"
}
run() { # DIR args... -> exit code; output in DIR/out
    d=$1; shift
    (cd "$d/repo" && STUB_STATE="$d/state" GH="$WORK/bin/gh" MAKE=true \
        sh scripts/release.sh "$@" > "$d/out" 2>&1)
}
calls() { grep -c -- "$2" "$1/state/calls" 2>/dev/null || echo 0; }

# R1: nothing published -> publish once, and the result is verified.
d=$(fresh r1)
run "$d" production v1.0.0; rc=$?
[ $rc = 0 ] && [ "$(calls "$d" 'skill publish --tag')" = 1 ] &&
    check yes 'R1 no tag: publishes once and verifies' || check no 'R1 no tag: publishes once and verifies'

# R2: rerun on the same commit -> a no-op, green, no second publish.
run "$d" production v1.0.0; rc=$?
[ $rc = 0 ] && [ "$(calls "$d" 'skill publish --tag')" = 1 ] && grep -q 'already published' "$d/out" &&
    check yes 'R2 rerun: nothing to do, exit 0' || check no 'R2 rerun: nothing to do, exit 0'

# R3: a publish that stopped after the tag -> the rerun creates only the release.
d=$(fresh r3)
STUB_PUBLISH=tag-only run "$d" production v1.0.0; first=$?
run "$d" production v1.0.0; rc=$?
[ $first != 0 ] && [ $rc = 0 ] && [ "$(calls "$d" 'release create v1.0.0')" = 1 ] &&
    [ "$(calls "$d" 'skill publish --tag')" = 1 ] && [ -f "$d/state/release-v1.0.0" ] &&
    check yes 'R3 tag without release: rerun resumes with release create' ||
    check no  'R3 tag without release: rerun resumes with release create'

# R4: the tag exists on another commit -> refuse, publish nothing.
d=$(fresh r4)
(cd "$d/repo" && git tag -a v1.0.0 -m x HEAD~1 && git push -q origin v1.0.0)
run "$d" production v1.0.0; rc=$?
[ $rc = 1 ] && [ "$(calls "$d" 'skill publish --tag')" = 0 ] && grep -q 'not at HEAD' "$d/out" &&
    check yes 'R4 tag on another commit: refuses' || check no 'R4 tag on another commit: refuses'

# R5: a publish that claims success and leaves nothing -> loud failure.
d=$(fresh r5)
STUB_PUBLISH=nothing run "$d" production v1.0.0; rc=$?
[ $rc = 1 ] && grep -q "not 'done'" "$d/out" &&
    check yes 'R5 success without a release is caught' || check no 'R5 success without a release is caught'

# R6: status reports each state by name.
d=$(fresh r6)
s1=$(cd "$d/repo" && STUB_STATE="$d/state" GH="$WORK/bin/gh" MAKE=true sh scripts/release.sh status v2.0.0)
(cd "$d/repo" && git tag -a v2.0.0 -m x && git push -q origin v2.0.0)
s2=$(cd "$d/repo" && STUB_STATE="$d/state" GH="$WORK/bin/gh" MAKE=true sh scripts/release.sh status v2.0.0)
touch "$d/state/release-v2.0.0"
s3=$(cd "$d/repo" && STUB_STATE="$d/state" GH="$WORK/bin/gh" MAKE=true sh scripts/release.sh status v2.0.0)
[ "$s1 $s2 $s3" = "none resume done" ] &&
    check yes 'R6 status: none -> resume -> done' || check no "R6 status: none -> resume -> done (got: $s1 $s2 $s3)"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
