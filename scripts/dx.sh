#!/bin/sh
# dx.sh --- one tmux session holding everything needed to work on this project.
#
#   ./scripts/dx.sh          create (or reuse) the session and print how to attach
#   ./scripts/dx.sh --attach create it, then attach
#   ./scripts/dx.sh --kill   tear it down, REPL and proxy included
#
# Four windows, because the four things you actually do are separate concerns:
#
#   edit     emacs -nw on a PROJECT-LOCAL profile (never your ~/.emacs.d)
#   repl     the logged socket REPL and its proxy, plus their status
#   harness  the metadata validators, re-run when a watched file changes
#   shell    a plain shell at the project root
#
# The session name is derived from the checkout, so two worktrees get two
# sessions instead of fighting over one -- the same reasoning as the derived test
# port in tests/test-proxy.sh.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

SLUG=$(basename "$ROOT")
SESSION="dx-$SLUG"
EMACS_DIR="$ROOT/.dx-emacs"

command -v tmux >/dev/null 2>&1 || { echo "dx: tmux is not on PATH" >&2; exit 1; }

case ${1:-} in
    --kill)
        gmake stop >/dev/null 2>&1 || true
        tmux kill-session -t "$SESSION" 2>/dev/null && echo "dx: killed $SESSION" \
            || echo "dx: no session $SESSION"
        exit 0
        ;;
esac

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "dx: session $SESSION already exists"
    [ "${1:-}" = "--attach" ] && exec tmux attach -t "$SESSION"
    echo "dx: attach with  tmux attach -t $SESSION"
    exit 0
fi

# --- the project-local Emacs profile --------------------------------------
#
# --init-directory landed in Emacs 29. Without it, emacs would silently load the
# user's real configuration, which is the opposite of what a project profile is
# for -- so assert rather than fall back.
EMACS_OK=1
if command -v emacs >/dev/null 2>&1; then
    EMACS_MAJOR=$(emacs --version 2>/dev/null | sed -n '1s/[^0-9]*\([0-9]*\).*/\1/p')
    if [ -z "$EMACS_MAJOR" ] || [ "$EMACS_MAJOR" -lt 29 ]; then
        echo "dx: emacs $EMACS_MAJOR has no --init-directory; the edit window will be bare" >&2
        EMACS_OK=0
    fi
else
    echo "dx: emacs is not on PATH; the edit window will be a shell" >&2
    EMACS_OK=0
fi

mkdir -p "$EMACS_DIR"
[ -f "$ROOT/emacs/init.el" ] && cp "$ROOT/emacs/init.el" "$EMACS_DIR/init.el"

# Install packages HERE, in batch, before any interactive Emacs opens. An
# interactive start that contacts melpa.org leaves a pane showing "Contacting
# host: ..." for as long as the network takes, which is indistinguishable in a
# capture from a profile that failed to load. Batch also fails loudly.
if [ "$EMACS_OK" = 1 ] && [ -f "$EMACS_DIR/init.el" ]; then
    echo "dx: resolving emacs packages (batch; first run downloads)..."
    if DX_INSTALL_PACKAGES=1 emacs --batch -l "$EMACS_DIR/init.el" \
            --eval '(princ (format "dx: geiser=%s paredit=%s keycast=%s missing=%S\n"
                                   (featurep (quote geiser-guile))
                                   (fboundp (quote paredit-mode))
                                   (featurep (quote keycast))
                                   guile-skills-dx-missing))' 2>&1 | tail -3; then
        :
    else
        echo "dx: package resolution failed; the edit window will still open" >&2
    fi
fi

# Hand the ports and load path to elisp rather than letting it re-derive them and
# disagree with the shell. One source of truth, and it is the shell.
PATHS=''
for c in "$ROOT/scripts/lib/guile-repl-paths.sh" \
         "$ROOT/skills/guile-repl-server/scripts/guile-repl-paths.sh"; do
    [ -r "$c" ] && PATHS=$c && break
done
if [ -n "$PATHS" ]; then
    # shellcheck source=/dev/null
    . "$PATHS"
fi
LOAD_FLAGS=''
if [ -x "$ROOT/scripts/guile-project-detect.sh" ]; then
    LOAD_FLAGS=$("$ROOT/scripts/guile-project-detect.sh" -L 2>/dev/null)
fi
{
    printf ';;; project.el --- written by scripts/dx.sh; do not edit\n'
    printf '(defvar guile-skills-dx-repl-port %s)\n'  "${GUILE_REPL_PORT:-0}"
    printf '(defvar guile-skills-dx-proxy-port %s)\n' "${GUILE_REPL_PROXY_PORT:-0}"
    # nil, not an empty defvar: guile-project-detect.sh may not exist on this
    # branch, and `(defvar x )' declares x without a value, so init.el's
    # (boundp 'x) check silently reports nothing rather than saying why.
    if [ -n "${LOAD_FLAGS:-}" ]; then
        printf '(defvar guile-skills-dx-load-path %s)\n' \
            "$(printf '%s' "$LOAD_FLAGS" | sed 's/-L //g' |
               awk '{printf "(quote ("; for(i=1;i<=NF;i++) printf "\"%s\" ", $i; printf "))"}')"
    else
        printf '(defvar guile-skills-dx-load-path nil)  ; no detector on this branch\n'
    fi
    if [ -n "${GUILE_REPL_DIR:-}" ]; then
        printf '(defvar guile-skills-dx-log-dir "%s")\n' "$GUILE_REPL_DIR"
    fi
} > "$EMACS_DIR/project.el"

# --- build the session ----------------------------------------------------
tmux new-session -d -s "$SESSION" -c "$ROOT" -n edit -x 200 -y 50
if [ "$EMACS_OK" = 1 ]; then
    tmux send-keys -t "$SESSION:edit" \
        "emacs -nw --init-directory=$EMACS_DIR" Enter
else
    tmux send-keys -t "$SESSION:edit" "echo 'emacs unavailable; see dx output'" Enter
fi

tmux new-window -t "$SESSION" -n repl -c "$ROOT"
tmux send-keys -t "$SESSION:repl" "gmake start && gmake status && gmake paths" Enter

tmux new-window -t "$SESSION" -n harness -c "$ROOT"
tmux send-keys -t "$SESSION:harness" "./scripts/dx-harness.sh" Enter

tmux new-window -t "$SESSION" -n shell -c "$ROOT"
tmux select-window -t "$SESSION:edit"

echo "dx: session $SESSION created"
echo "    windows   edit (emacs -nw) | repl | harness | shell"
echo "    emacs     ${EMACS_DIR}  (project-local; your ~/.emacs.d is untouched)"
echo "    repl      ${GUILE_REPL_PORT:-?} -> proxy ${GUILE_REPL_PROXY_PORT:-?}"
echo "    connect   in emacs: C-c C-g"
echo "    attach    tmux attach -t $SESSION"
echo "    teardown  ./scripts/dx.sh --kill"

[ "${1:-}" = "--attach" ] && exec tmux attach -t "$SESSION"
exit 0
