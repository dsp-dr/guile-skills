#!/bin/sh
# test-dir-locals.sh --- regressions for skills/emacs-setup/scripts/guile-dir-locals.sh.
#
# Every case runs in its own mktemp project, under emacs -Q, so neither the
# user's Emacs configuration nor this checkout's layout can help or hurt
# (docs/isolation.org). Nothing binds a port: --verify only computes ports.
#
# A missing emacs is a FAILURE, not a skip. A check that skips itself for a
# missing tool reads as a pass (6143228).

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GEN="$ROOT/skills/emacs-setup/scripts/guile-dir-locals.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0
failed=0
check() { # yes|no label
    if [ "$1" = yes ]; then passed=$((passed + 1)); printf '  ok    %s\n' "$2"
    else failed=$((failed + 1)); printf '  FAIL  %s\n' "$2"; fi
}

if ! command -v emacs >/dev/null 2>&1; then
    echo "test-dir-locals: emacs is not on PATH; these regressions cannot run" >&2
    exit 1
fi
echo "test-dir-locals: $(emacs --version | head -1)"

# project NAME LAYOUT -> a git repo whose modules live under LAYOUT ("." = root).
# The name carries a dot on purpose: the slug turns "." into "-", and Emacs and
# the shell must agree on that.
project() {
    d="$WORK/$1"
    mkdir -p "$d"
    (cd "$d" && git init -q)
    if [ "$2" = . ]; then
        printf '(define-module (%s))\n' "$1" | tr '.' '-' > "$d/main.scm"
    else
        mkdir -p "$d/$2"
        printf '(define-module (%s core))\n' "$2" > "$d/$2/core.scm"
        printf '(define-module (%s util))\n' "$2" > "$d/$2/util.scm"
    fi
    printf '%s' "$d"
}

verify_rc() { (cd "$1" && sh "$GEN" --verify >/dev/null 2>&1); echo $?; }

# D1: a non-src layout (the guile-irc shape) round-trips.
p=$(project irc.proj irc)
(cd "$p" && sh "$GEN" > .dir-locals.el)
if grep -q '"irc"' "$p/.dir-locals.el" && ! grep -q '"src"' "$p/.dir-locals.el"; then
    check yes 'D1 load path comes from the detector, not from src/'
else
    check no  'D1 load path comes from the detector, not from src/'
fi
[ "$(verify_rc "$p")" = 0 ] && check yes 'D2 --verify: Emacs and the shell agree (irc/ layout)' \
                            || check no  'D2 --verify: Emacs and the shell agree (irc/ layout)'

# D3: modules at the repository root.
r=$(project root.proj .)
(cd "$r" && sh "$GEN" > .dir-locals.el)
[ "$(verify_rc "$r")" = 0 ] && check yes 'D3 --verify: repository-root layout' \
                            || check no  'D3 --verify: repository-root layout'

# D4: no binary is pinned outside the probe list.
if grep -q 'geiser-guile-binary "' "$p/.dir-locals.el"; then
    check no  'D4 geiser-guile-binary is probed, never pinned'
else
    check yes 'D4 geiser-guile-binary is probed, never pinned'
fi

# Planted faults: --verify must fail on each.
cp "$p/.dir-locals.el" "$WORK/good.el"
sed 's/(+ 37000 /(+ 37001 /' "$WORK/good.el" > "$p/.dir-locals.el"
[ "$(verify_rc "$p")" != 0 ] && check yes 'D5 planted port drift is caught' \
                             || check no  'D5 planted port drift is caught'
sed 's/(quote ("irc"))/(quote ("src"))/; s/'"'"'("irc")/'"'"'("src")/' "$WORK/good.el" > "$p/.dir-locals.el"
[ "$(verify_rc "$p")" != 0 ] && check yes 'D6 planted src/ assumption is caught' \
                             || check no  'D6 planted src/ assumption is caught'
rm -f "$p/.dir-locals.el"
[ "$(verify_rc "$p")" != 0 ] && check yes 'D7 a missing .dir-locals.el is a failure' \
                             || check no  'D7 a missing .dir-locals.el is a failure'

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
