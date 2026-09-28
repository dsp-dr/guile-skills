#!/bin/sh
# sync-secrets.sh --- push secrets from the local pass store into GitHub.
#
#   scripts/sync-secrets.sh status        # manifest vs. what GitHub actually holds
#   scripts/sync-secrets.sh push          # set every manifest entry from pass
#   scripts/sync-secrets.sh push NAME...  # just these
#   scripts/sync-secrets.sh remove NAME   # delete one from GitHub (asks first)
#
# pass is the source of truth; GitHub is a replica. The manifest is
# scripts/secrets.map -- names only, safe to commit. Values only ever move
# local -> GitHub, never the other way, because the other way is impossible:
#
#   *** GitHub never returns a secret's value. ***
#
# So `status' can compare presence and updated_at and nothing else. It cannot
# tell you the replica matches pass, only that something is set and when. If you
# are unsure, re-push: setting a secret to its current value is harmless.
#
# Not in bin/: RELEASING.md treats bin/*.sh as this plugin's public interface,
# where an argument change is a major version bump. This is repo administration.
#
# Secret hygiene, same rules as docs/secrets.md:
#   - values reach gh on stdin, never via --body, so they stay out of argv/ps
#   - the trailing newline is stripped explicitly; gh does not strip it, and a
#     secret with a stray \n fails authentication somewhere far away with no
#     hint that whitespace is the cause
#   - nothing is echoed, and no temporary file is written
#   - do not add `set -x' to this script

set -u

ACTION=${1:-status}
[ $# -gt 0 ] && shift

HERE=$(dirname "$0")
MANIFEST=${MANIFEST:-$HERE/secrets.map}

warn() { echo "sync-secrets: $*" >&2; }
die() { warn "$*"; exit 1; }

command -v gh >/dev/null 2>&1   || die "gh is required but not on PATH"
command -v pass >/dev/null 2>&1 || die "pass is required but not on PATH"
[ -r "$MANIFEST" ]              || die "no manifest at $MANIFEST"

REPO=${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}
[ -n "${REPO:-}" ] || die "cannot determine the repo; set REPO=owner/name"

# Strip comments and blank lines; emit "name path app".
manifest() {
    sed -e 's/#.*//' "$MANIFEST" |
    while read -r name path app; do
        [ -n "${name:-}" ] || continue
        printf '%s %s %s\n' "$name" "$path" "${app:-actions}"
    done
}

# Value on stdin with no trailing newline: command substitution eats the
# newline, printf adds none, and printf is a shell builtin so the value never
# becomes a process argument.
push_one() {
    name=$1 path=$2 app=$3

    if ! pass show "$path" >/dev/null 2>&1; then
        warn "$path is not in pass (needed for $name)"
        return 1
    fi
    value=$(pass show "$path" 2>/dev/null | head -n 1)
    if [ -z "$value" ]; then
        warn "$path decrypted to an empty first line; refusing to push $name"
        return 1
    fi

    if ! printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --app "$app"; then
        warn "failed to set $name"
        return 1
    fi
    printf '  pushed %-28s <- %s  (%s)\n' "$name" "$path" "$app"
}

remote_secrets() {
    gh secret list --repo "$REPO" --app "$1" --json name,updatedAt \
        --jq '.[] | "\(.name)\t\(.updatedAt)"' 2>/dev/null
}

case $ACTION in

status)
    printf 'repo      %s\n' "$REPO"
    printf 'manifest  %s\n\n' "$MANIFEST"

    count=$(manifest | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        echo 'manifest is empty -- nothing is meant to be synced yet.'
    else
        printf '%-28s %-10s %-9s %s\n' SECRET APP 'IN PASS' 'ON GITHUB'
        manifest | while read -r name path app; do
            if pass show "$path" >/dev/null 2>&1; then in_pass=yes; else in_pass=MISSING; fi
            seen=$(remote_secrets "$app" | awk -F'\t' -v n="$name" '$1 == n { print $2 }')
            printf '%-28s %-10s %-9s %s\n' "$name" "$app" "$in_pass" "${seen:-absent}"
        done
    fi

    # Drift in the other direction: something on GitHub that pass does not
    # account for. Reported, never deleted -- it may predate this manifest.
    for app in actions dependabot; do
        remote_secrets "$app" | cut -f1 | while read -r remote; do
            [ -n "${remote:-}" ] || continue
            manifest | awk -v n="$remote" '$1 == n { found = 1 } END { exit !found }' ||
                printf 'unmanaged %s secret on GitHub, not in the manifest: %s\n' "$app" "$remote"
        done
    done
    ;;

push)
    # Loop from a file rather than a pipe: a `while read' on the right of a pipe
    # runs in a subshell, where a failure cannot be reported back to this script.
    # The manifest holds names only, so a temporary file leaks nothing.
    tmp=$(mktemp) || die "cannot create a temporary file"
    trap 'rm -f "$tmp"' EXIT HUP INT TERM

    if [ $# -eq 0 ]; then
        manifest > "$tmp"
    else
        for want in "$@"; do
            line=$(manifest | awk -v n="$want" '$1 == n')
            [ -n "$line" ] || die "$want is not in $MANIFEST"
            printf '%s\n' "$line" >> "$tmp"
        done
    fi

    if [ ! -s "$tmp" ]; then
        echo 'nothing in the manifest to push.'
        exit 0
    fi

    failed=0
    while read -r name path app; do
        [ -n "${name:-}" ] || continue
        push_one "$name" "$path" "${app:-actions}" || failed=1
    done < "$tmp"

    [ "$failed" -eq 0 ] || die "one or more secrets did not push; GitHub is now partly stale"
    echo 'done.'
    ;;

remove)
    name=${1:-} ; [ -n "$name" ] || die "remove needs a secret name"
    app=$(manifest | awk -v n="$name" '$1 == n { print $3 }')
    app=${app:-actions}
    printf 'delete %s secret %s from %s? [y/N] ' "$app" "$name" "$REPO"
    read -r answer </dev/tty || answer=n
    case $answer in
        y|Y) gh secret delete "$name" --repo "$REPO" --app "$app" && echo "deleted $name" ;;
        *)   die "aborted" ;;
    esac
    ;;

--help|-h|help)
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    ;;

*)
    die "unknown action $ACTION (try --help)"
    ;;
esac
