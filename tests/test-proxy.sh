#!/bin/sh
# test-proxy.sh --- regression tests for the failures in EXPERIMENTS.org.
#
# Each test names the experiment it locks down, so a future change that
# reintroduces a silent failure fails here instead of in a debugging session.
#
# Uses a port well away from the derived one so it cannot fight a real session,
# and derived per checkout so it cannot fight another WORKTREE either: cleanup
# below is `pkill -f "listen=$PORT"', so with a fixed port a run in one worktree
# kills the REPL of a run in another. That was measured on 2026-09-29, as one
# 6-passed-1-failed run that passed on its own -- the same pkill-by-pattern
# hazard the roadmap files as A4, inside the test suite.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Base 39000 keeps the test range clear of the 37000 project range.
if [ -z "${TEST_PORT:-}" ]; then
    _test_slug=$(printf '%s' "$ROOT" | tr '/.' '--')
    TEST_PORT=$((39000 + $(printf '%s' "$_test_slug" | cksum | cut -d' ' -f1) % 900))
fi
PORT=$TEST_PORT
PROXY_PORT=$((PORT + 1))
WORK=$(mktemp -d)
LOG="$WORK/repl.log"
passed=0
failed=0

# Same probe order as scripts/lib/guile-repl-paths.sh: FreeBSD names it guile3, Debian
# and Ubuntu name it guile-3.0, Homebrew names it guile.
for guile_candidate in guile3 guile-3.0 guile; do
    command -v "$guile_candidate" >/dev/null 2>&1 && { GUILE=$guile_candidate; break; }
done
GUILE=${GUILE:-guile}
if nc -h 2>&1 | grep -q '\-N'; then NCS="-N"; else NCS=""; fi

cleanup() {
    pkill -f "guile-repl-proxy.scm --listen $PROXY_PORT" 2>/dev/null
    pkill -f "listen=$PORT" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

ok()   { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL  %s\n' "$1"; }
check(){ if [ "$1" = "yes" ]; then ok "$2"; else fail "$2"; fi; }

echo "test-proxy: $GUILE, port $PORT -> proxy $PROXY_PORT"

# --- bring up REPL and proxy ----------------------------------------------
$GUILE --debug --listen="$PORT" -c '(sleep 90)' >/dev/null 2>&1 &
sleep 2
"$ROOT/skills/guile-repl-proxy/scripts/guile-repl-proxy.scm" --listen "$PROXY_PORT" --target "$PORT" --log "$LOG" \
    >"$WORK/proxy.err" 2>&1 &
sleep 3

# --- E1: the socket REPL answers -----------------------------------------
out=$(printf '(+ 1 1)\n' | nc $NCS 127.0.0.1 "$PORT" 2>/dev/null)
case $out in *'$1 = 2'*) check yes 'E1 repl evaluates over its own socket';;
             *)          check no  'E1 repl evaluates over its own socket';; esac

# --- E3: a reply survives the client half-closing -------------------------
# This is the one that silently forwarded requests and dropped every response.
out=$(printf '(* 6 7)\n' | nc $NCS 127.0.0.1 "$PROXY_PORT" 2>/dev/null)
case $out in *'42'*) check yes 'E3 reply survives client half-close';;
             *)      check no  'E3 reply survives client half-close';; esac

# --- E2: the transcript is whole lines, not one byte each -----------------
if grep -qa '^-> .* (\* 6 7)$' "$LOG"; then
    check yes 'E2 transcript logs whole lines'
else
    check no  'E2 transcript logs whole lines'
fi

# --- E3b: --debug is live, so ,trace produces output ----------------------
out=$(printf '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))\n,trace (fib 3)\n' \
        | nc $NCS 127.0.0.1 "$PROXY_PORT" 2>/dev/null)
n=$(printf '%s\n' "$out" | grep -ca 'trace: ')
if [ "$n" -ge 5 ]; then check yes "E3b ,trace returns a call tree ($n lines)"
else                   check no  "E3b ,trace returns a call tree ($n lines)"; fi

# --- E6: a persistent connection survives several round-trips -------------
# nc -N half-closes immediately; Geiser does not. Opposite halves of the
# connection lifecycle, and only this shape catches a broken persistent path.
out=$({ printf '(+ 2 2)\n'; sleep 2; printf '(+ 3 3)\n'; sleep 2; } \
        | timeout 12 nc 127.0.0.1 "$PROXY_PORT" 2>/dev/null)
if printf '%s\n' "$out" | grep -qa '= 4' && printf '%s\n' "$out" | grep -qa '= 6'; then
    check yes 'E6 persistent connection, multiple round-trips'
else
    check no  'E6 persistent connection, multiple round-trips'
fi

# --- E4: a second proxy on a taken port fails loudly ----------------------
# It used to die silently while the stale one kept serving and kept logging.
err=$("$ROOT/skills/guile-repl-proxy/scripts/guile-repl-proxy.scm" --listen "$PROXY_PORT" --target "$PORT" \
        --log "$WORK/second.log" 2>&1; echo "rc=$?")
case $err in
    *'cannot bind'*rc=1*) check yes 'E4 duplicate proxy refuses the taken port';;
    *)                    check no  'E4 duplicate proxy refuses the taken port';;
esac

# --- E5: rotation past the threshold --------------------------------------
pkill -f "guile-repl-proxy.scm --listen $PROXY_PORT" 2>/dev/null
sleep 1
ROT="$WORK/rot.log"
dd if=/dev/zero bs=1024 count=4200 2>/dev/null | tr '\0' 'x' > "$ROT"
"$ROOT/skills/guile-repl-proxy/scripts/guile-repl-proxy.scm" --listen "$PROXY_PORT" --target "$PORT" --log "$ROT" \
    >/dev/null 2>&1 &
sleep 3
if [ -f "$ROT.1" ] && [ "$(wc -c < "$ROT")" -lt 4194304 ]; then
    check yes 'E5 log rotates past 4 MiB'
else
    check no  'E5 log rotates past 4 MiB'
fi

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
