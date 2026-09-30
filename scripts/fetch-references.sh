#!/bin/sh
# fetch-references.sh --- pull the pinned Emacs, Guile and Geiser sources to a local corpus.
#
#   scripts/fetch-references.sh            # fetch what is missing, verify everything
#   scripts/fetch-references.sh --list     # where each entry lives, and whether present
#   scripts/fetch-references.sh NAME...    # only these names (e.g. guile geiser)
#
# Reviewers -- human or agent -- read these trees instead of recalling how
# Geiser or Guile behaves: "the source says" beats "I remember". The manifest is
# scripts/references.tsv.
#
# The corpus lives OUTSIDE the repository, shared by every worktree on the host:
#   ${GUILE_SKILLS_REFERENCE:-${XDG_CACHE_HOME:-$HOME/.cache}/guile-skills/reference}/<name>-<version>/
# Entries are immutable once verified; a version change is a new directory. So
# worktrees can share it without contending (docs/isolation.org).
#
# Verification: a tar entry must match its pinned sha256; a git entry must
# resolve to its pinned commit. An entry pinned "-" is fetched, its sha256 is
# PRINTED, and the run fails -- trust on first use is written into the manifest
# by a human, not granted by the script.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST=${REFERENCES_MANIFEST:-$ROOT/scripts/references.tsv}
DEST=${GUILE_SKILLS_REFERENCE:-${XDG_CACHE_HOME:-$HOME/.cache}/guile-skills/reference}

LIST=0
[ "${1:-}" = "--list" ] && { LIST=1; shift; }
ONLY=" $* "

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

mkdir -p "$DEST"
# A pipeline runs the loop in a subshell, so a variable set there is lost and
# the exit code would lie. Failures are recorded in a file instead.
FAILED=$(mktemp)
trap 'rm -f "$FAILED"' EXIT
tab=$(printf '\t')
grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' |
while IFS="$tab" read -r name version kind url pin; do
    case $ONLY in "  ") ;; *" $name "*) ;; *) continue ;; esac
    dir="$DEST/$name-$version"
    if [ "$LIST" -eq 1 ]; then
        printf '%-14s %-18s %s  %s\n' "$name" "$version" "$([ -f "$dir/.verified" ] && echo present || echo MISSING)" "$dir"
        continue
    fi
    if [ -f "$dir/.verified" ]; then
        printf '  ok       %s-%s (verified %s)\n' "$name" "$version" "$(cat "$dir/.verified")"
        continue
    fi
    tmp="$DEST/.partial-$name-$version"
    rm -rf "$tmp"; mkdir -p "$tmp"
    case $kind in
        tar)
            archive="$tmp/${url##*/}"
            curl -fsSL -o "$archive" "$url" || { echo "  FAIL     $name-$version: download failed" >&2; echo "$name-$version" >> "$FAILED"; continue; }
            got=$(sha256 "$archive")
            if [ "$pin" = "-" ]; then
                echo "  UNPINNED $name-$version sha256 $got -- write it into references.tsv, then rerun" >&2
                echo "$name-$version" >> "$FAILED"; continue
            fi
            [ "$got" = "$pin" ] || { echo "  FAIL     $name-$version: sha256 $got, pinned $pin" >&2; echo "$name-$version" >> "$FAILED"; continue; }
            mkdir -p "$tmp/src" && tar -xJf "$archive" -C "$tmp/src" --strip-components=1 && rm -f "$archive" ;;
        git)
            git init -q "$tmp/src" &&
            git -C "$tmp/src" fetch -q --depth 1 "$url" "$pin" &&
            git -C "$tmp/src" checkout -q FETCH_HEAD ||
                { echo "  FAIL     $name-$version: cannot fetch $pin from $url" >&2; echo "$name-$version" >> "$FAILED"; continue; }
            got=$(git -C "$tmp/src" rev-parse HEAD)
            [ "$got" = "$pin" ] || { echo "  FAIL     $name-$version: HEAD $got, pinned $pin" >&2; echo "$name-$version" >> "$FAILED"; continue; }
            rm -rf "$tmp/src/.git" ;;
        *)  echo "  FAIL     $name-$version: unknown kind $kind" >&2; echo "$name-$version" >> "$FAILED"; continue ;;
    esac
    rm -rf "$dir" && mv "$tmp/src" "$dir" && rm -rf "$tmp"
    chmod -R a-w "$dir" 2>/dev/null
    chmod u+w "$dir" && date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/.verified" && chmod u-w "$dir"
    printf '  fetched  %s-%s -> %s\n' "$name" "$version" "$dir"
done

if [ -s "$FAILED" ]; then
    echo "fetch-references: $(wc -l < "$FAILED" | tr -d ' ') entr(ies) not verified: $(tr '\n' ' ' < "$FAILED")" >&2
    exit 1
fi
[ "$LIST" -eq 1 ] || echo "fetch-references: every requested entry verified under $DEST"
