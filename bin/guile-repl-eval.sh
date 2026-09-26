#!/bin/sh
# guile-repl-eval.sh --- send forms to this project's Guile REPL, print the reply.
#
# The analogue of clj-nrepl-eval / brepl / nreplctl in the Clojure ecosystem,
# except that Guile needs no bridge process: `guile3 --listen' is the server.
#
#   ./bin/guile-repl-eval.sh '(+ 1 1)'
#   echo '(use-modules (my mod))' | ./bin/guile-repl-eval.sh
#   ./bin/guile-repl-eval.sh --raw ',trace (fib 4)'
#
# Connects to the PROXY port by default, so every evaluation is recorded in the
# project transcript. --direct bypasses the proxy (and the log).
#
# The REPL greets every connection with an eight-line banner and ends each reply
# with a prompt. Both are stripped unless --raw is given: an agent reading this
# output should see the value, not the copyright notice.

set -u

. "$(dirname "$0")/guile-repl-paths.sh"

RAW=0
PORT=$GUILE_REPL_PROXY_PORT
while [ $# -gt 0 ]; do
    case $1 in
        --raw)    RAW=1; shift ;;
        --direct) PORT=$GUILE_REPL_PORT; shift ;;
        --port)   PORT=$2; shift 2 ;;
        --help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) break ;;
    esac
done

if [ $# -gt 0 ]; then
    PROGRAM=$*
else
    PROGRAM=$(cat)
fi

if nc -h 2>&1 | grep -q '\-N'; then NC_SHUTDOWN="-N"; else NC_SHUTDOWN=""; fi

reply=$(printf '%s\n' "$PROGRAM" | nc $NC_SHUTDOWN 127.0.0.1 "$PORT" 2>/dev/null) || {
    echo "guile-repl-eval: nothing listening on 127.0.0.1:$PORT" >&2
    echo "  start one with: ./bin/guile-repl-server.sh" >&2
    exit 1
}

if [ -z "$reply" ]; then
    echo "guile-repl-eval: no reply from 127.0.0.1:$PORT" >&2
    exit 1
fi

if [ "$RAW" -eq 1 ]; then
    printf '%s\n' "$reply"
    exit 0
fi

# Drop everything up to and including the "Enter `,help' for help." banner line,
# then strip the trailing prompt. Falls back to printing everything if the
# banner is absent (it is, on a connection the proxy has already greeted).
printf '%s\n' "$reply" |
    awk '
        /Enter `,help. for help\./ { seen = 1; next }
        { if (seen) print; else buffer = buffer $0 "\n" }
        END { if (!seen) printf "%s", buffer }
    ' |
    sed -e 's/^scheme@([^)]*)> *//' -e '/^[[:space:]]*$/d'
