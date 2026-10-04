#!/bin/sh
# guile-repl-server.sh --- start this project's Guile REPL and its logging proxy.
#
#   ${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh            # REPL on PORT, proxy on PORT+1
#   ${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh --no-proxy # REPL only
#   ${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh --stop     # stop both
#   ${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh --status    # what is actually listening
#
# --debug is not optional. Without it Guile starts the fast VM engine and the
# tracing and breakpoint meta-commands silently do nothing -- ,trace prints no
# lines and raises no error. See EXPERIMENTS.org E3.
#
# The REPL binds 127.0.0.1 only, and so does the proxy. Keep it that way: a
# socket REPL is arbitrary code execution by design.

set -u

. "$(dirname "$0")/guile-repl-paths.sh"

SRC_DIR=${SRC_DIR:-src}
PROXY=1
ACTION=start

while [ $# -gt 0 ]; do
    case $1 in
        --no-proxy) PROXY=0; shift ;;
        --stop)     ACTION=stop; shift ;;
        --status)   ACTION=status; shift ;;
        --help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "repl-server: unknown option $1" >&2; exit 2 ;;
    esac
done

listening() {
    # sockstat on FreeBSD, lsof elsewhere; fall back to a connection attempt.
    if command -v sockstat >/dev/null 2>&1; then
        sockstat -4 -l 2>/dev/null | grep -q ":$1\$\|:$1 "
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
    else
        printf '' | nc -z 127.0.0.1 "$1" 2>/dev/null
    fi
}

case $ACTION in
  status)
    for pair in "repl:$GUILE_REPL_PORT" "proxy:$GUILE_REPL_PROXY_PORT"; do
        name=${pair%%:*}; port=${pair##*:}
        if listening "$port"; then
            printf '%-6s %-6s listening\n' "$name" "$port"
        else
            printf '%-6s %-6s down\n' "$name" "$port"
        fi
    done
    printf 'log    %s\n' "$GUILE_REPL_DIR/repl.log"
    exit 0 ;;
  stop)
    pkill -f "listen=$GUILE_REPL_PORT" 2>/dev/null && echo "stopped repl on $GUILE_REPL_PORT"
    pkill -f "guile-repl-proxy.scm --listen $GUILE_REPL_PROXY_PORT" 2>/dev/null &&
        echo "stopped proxy on $GUILE_REPL_PROXY_PORT"
    exit 0 ;;
esac

# A stale server from an earlier session is the failure that wasted the most
# time building this (EXPERIMENTS.org E4): it holds the port, the new process
# never accepts, and its transcript goes to a log nobody is reading. Refuse
# rather than guess.
if listening "$GUILE_REPL_PORT"; then
    echo "repl-server: 127.0.0.1:$GUILE_REPL_PORT is already in use." >&2
    echo "  reuse it, or stop it with: $0 --stop" >&2
    exit 1
fi

mkdir -p "$GUILE_REPL_DIR"

[ -d "$SRC_DIR" ] && LOAD_PATH="-L $SRC_DIR" || LOAD_PATH=""

# shellcheck disable=SC2086
$GUILE --debug $LOAD_PATH --listen="$GUILE_REPL_PORT" -c '(let forever () (sleep 86400) (forever))' \
    >"$GUILE_REPL_DIR/repl.stderr" 2>&1 &
echo "repl   $GUILE_REPL_PORT  ($GUILE --debug, load path: ${SRC_DIR:-none})"

if [ "$PROXY" -eq 1 ]; then
    if listening "$GUILE_REPL_PROXY_PORT"; then
        echo "repl-server: proxy port $GUILE_REPL_PROXY_PORT already in use, skipping" >&2
    else
        # Wait for the REPL before the proxy tries to reach it.
        n=0
        while [ $n -lt 25 ] && ! listening "$GUILE_REPL_PORT"; do
            n=$((n + 1)); sleep 0.2 2>/dev/null || sleep 1
        done
        # `sh' rather than executing it: an installed skill's files arrive
        # without the executable bit, and the proxy's shebang block is a POSIX
        # shell trampoline, so this works either way.
        sh "$(dirname "$0")/guile-repl-proxy.scm" \
            --listen "$GUILE_REPL_PROXY_PORT" \
            --target "$GUILE_REPL_PORT" \
            --log "$GUILE_REPL_DIR/repl.log" \
            >>"$GUILE_REPL_DIR/proxy.stderr" 2>&1 &
        echo "proxy  $GUILE_REPL_PROXY_PORT  -> $GUILE_REPL_PORT, logging to $GUILE_REPL_DIR/repl.log"
    fi
fi

echo "eval with: the repl-eval skill"
