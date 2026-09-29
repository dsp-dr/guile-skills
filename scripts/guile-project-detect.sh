#!/bin/sh
# guile-project-detect.sh --- find out how THIS project is laid out.
#
#   . guile-project-detect.sh     # sets GUILE_PROJECT_* below
#   ./guile-project-detect.sh     # prints a report
#   ./guile-project-detect.sh -L  # prints just the load-path flags
#
# Written because assuming src/ is wrong. Measured across 48 Scheme checkouts on
# nexus, 2026-09-29, by where (define-module ...) forms actually live:
#
#   src/                      22   the plurality, not a majority
#   a directory named for the project  5   the Guile/Guix idiom (guile-irc: irc/,
#                                         guile-cps-debugger: cps-debugger/)
#   the repository root        3
#   lib/, modules/, scheme/, experiments/, scripts/   1 each
#   no modules at all         13   scripts, not libraries
#
# So guile-repl-server.sh's SRC_DIR=${SRC_DIR:-src} is right less than half the
# time, and a REPL started with load path `none' fails on (use-modules ...) with
# no hint as to why. This script is the primitive that fixes that, and the same
# answer configures Geiser.
#
# Sets:
#   GUILE_PROJECT_ROOT       the repository root
#   GUILE_PROJECT_NAME       its basename
#   GUILE_PROJECT_MODULE_DIRS  space-separated, most modules first, "." for root
#   GUILE_PROJECT_LOAD_FLAGS   the same as `-L dir' arguments
#   GUILE_PROJECT_TEST_DIR   tests/, test/, t/ or empty
#   GUILE_PROJECT_BUILD      make | autotools | guix | none (may combine)
#   GUILE_PROJECT_HAS_SRFI64 1 or 0
#   GUILE                    guile3 | guile-3.0 | guile, probed not assumed

set -u

GUILE_PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GUILE_PROJECT_NAME=${GUILE_PROJECT_ROOT##*/}

# A module's directory is the one that makes its (define-module (a b)) path
# resolve, i.e. the prefix above the first component. Counting files per
# top-level directory and taking the busiest is a heuristic, but it is a
# heuristic over evidence rather than a default of src/.
_detect_module_dirs() {
    _candidates=$(
        grep -rl --include='*.scm' -e '(define-module' "$GUILE_PROJECT_ROOT" 2>/dev/null |
        sed "s|^$GUILE_PROJECT_ROOT/||" |
        grep -v -e '^\.git/' -e '/\.git/' -e '^node_modules/' -e '/node_modules/' \
                -e '^vendor/' -e '^submodules/' -e '^\.guix' |
        awk -F/ '{ print (NF > 1 ? $1 : ".") }' |
        sort | uniq -c | sort -rn | awk '{ print $2 }'
    )
    # Keep a candidate only if it is a real directory (or the root marker), and
    # cap at three: more than that is a monorepo, and guessing further is worse
    # than reporting what was found.
    _kept=''
    _n=0
    for _c in $_candidates; do
        [ "$_n" -ge 3 ] && break
        if [ "$_c" = "." ] || [ -d "$GUILE_PROJECT_ROOT/$_c" ]; then
            _kept="$_kept $_c"
            _n=$((_n + 1))
        fi
    done
    printf '%s' "${_kept# }"
}

GUILE_PROJECT_MODULE_DIRS=$(_detect_module_dirs)

GUILE_PROJECT_LOAD_FLAGS=''
for _d in $GUILE_PROJECT_MODULE_DIRS; do
    case $_d in
        .) GUILE_PROJECT_LOAD_FLAGS="$GUILE_PROJECT_LOAD_FLAGS -L $GUILE_PROJECT_ROOT" ;;
        *) GUILE_PROJECT_LOAD_FLAGS="$GUILE_PROJECT_LOAD_FLAGS -L $GUILE_PROJECT_ROOT/$_d" ;;
    esac
done
GUILE_PROJECT_LOAD_FLAGS=${GUILE_PROJECT_LOAD_FLAGS# }

GUILE_PROJECT_TEST_DIR=''
for _t in tests test t; do
    if [ -d "$GUILE_PROJECT_ROOT/$_t" ]; then
        GUILE_PROJECT_TEST_DIR=$_t
        break
    fi
done

GUILE_PROJECT_BUILD=''
[ -f "$GUILE_PROJECT_ROOT/configure.ac" ] && GUILE_PROJECT_BUILD="${GUILE_PROJECT_BUILD}autotools "
{ [ -f "$GUILE_PROJECT_ROOT/Makefile" ] || [ -f "$GUILE_PROJECT_ROOT/GNUmakefile" ] || \
  [ -f "$GUILE_PROJECT_ROOT/Makefile.am" ]; } && GUILE_PROJECT_BUILD="${GUILE_PROJECT_BUILD}make "
{ [ -f "$GUILE_PROJECT_ROOT/guix.scm" ] || [ -f "$GUILE_PROJECT_ROOT/manifest.scm" ]; } &&
    GUILE_PROJECT_BUILD="${GUILE_PROJECT_BUILD}guix "
GUILE_PROJECT_BUILD=${GUILE_PROJECT_BUILD:-none}
GUILE_PROJECT_BUILD=${GUILE_PROJECT_BUILD% }

if grep -rql --include='*.scm' -e 'srfi.64' -e 'test-begin' -e 'test-assert' \
        "$GUILE_PROJECT_ROOT" 2>/dev/null; then
    GUILE_PROJECT_HAS_SRFI64=1
else
    GUILE_PROJECT_HAS_SRFI64=0
fi

# Same probe order as guile-repl-paths.sh, and for the same reason (8178314):
# bare `guile' is 2.2.7 on some FreeBSD boxes and 3.x under Homebrew.
if [ -z "${GUILE:-}" ]; then
    for _cand in guile3 guile-3.0 guile; do
        if command -v "$_cand" >/dev/null 2>&1; then
            GUILE=$_cand
            break
        fi
    done
    GUILE=${GUILE:-guile}
fi

export GUILE_PROJECT_ROOT GUILE_PROJECT_NAME GUILE_PROJECT_MODULE_DIRS \
       GUILE_PROJECT_LOAD_FLAGS GUILE_PROJECT_TEST_DIR GUILE_PROJECT_BUILD \
       GUILE_PROJECT_HAS_SRFI64 GUILE

case ${0##*/} in
    guile-project-detect.sh)
        if [ "${1:-}" = "-L" ]; then
            printf '%s\n' "$GUILE_PROJECT_LOAD_FLAGS"
            exit 0
        fi
        printf 'project      %s\n' "$GUILE_PROJECT_NAME"
        printf 'root         %s\n' "$GUILE_PROJECT_ROOT"
        printf 'module dirs  %s\n' "${GUILE_PROJECT_MODULE_DIRS:-none found (scripts, not modules?)}"
        printf 'load path    %s\n' "${GUILE_PROJECT_LOAD_FLAGS:-none}"
        printf 'tests        %s\n' "${GUILE_PROJECT_TEST_DIR:-none}"
        printf 'build        %s\n' "$GUILE_PROJECT_BUILD"
        printf 'srfi-64      %s\n' "$([ "$GUILE_PROJECT_HAS_SRFI64" = 1 ] && echo yes || echo no)"
        printf 'guile        %s\n' "$(command -v "$GUILE" || echo 'NOT FOUND')"
        ;;
esac
