#!/bin/sh
# install-directory-webhook.sh --- create this repo's Anthropic plugin-directory
# push webhook, once. Both values come from pass; the script takes no arguments.
#
#   sh install-directory-webhook.sh
#   REPO=owner/name sh install-directory-webhook.sh
#
# Deliberately contains no here-document and builds no JSON by string
# interpolation, because those were the two actual faults when this was typed at
# a prompt: an indented `EOF' is invisible and never matches, and "$(...)" inside
# a JSON string is one stray quote from a 400. jq assembles the body, the secret
# arrives on jq's stdin, and no secret becomes a process argument.

set -u

REPO=${REPO:-dsp-dr/guile-skills}
PASS_URL="github/$REPO/directory-webhook-url"
PASS_SECRET="github/$REPO/directory-webhook-secret"

die() { echo "install-directory-webhook: $*" >&2; exit 1; }

for tool in gh jq pass; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not on PATH"
done

# --- pre-flight ----------------------------------------------------------

pass show "$PASS_URL" >/dev/null 2>&1 || die "no payload URL in pass.
  Store it first -- paste at the prompt, so there is no quoting to get wrong:
    pass insert -e $PASS_URL"

pass show "$PASS_SECRET" >/dev/null 2>&1 || die "no secret in pass at $PASS_SECRET"

url=$(pass show "$PASS_URL" | head -n 1)
[ -n "$url" ] || die "$PASS_URL decrypted to an empty first line"
[ -n "$(pass show "$PASS_SECRET" | head -n 1)" ] ||
    die "$PASS_SECRET decrypted to an empty first line; refusing to create an unsigned hook"

case $url in
    https://*) ;;
    *) die "payload URL in pass does not start with https:// -- is the entry right?" ;;
esac

hooks=$(gh api "repos/$REPO/hooks" 2>&1) || die "cannot list hooks on $REPO: $hooks"
dupe=$(printf '%s' "$hooks" | jq -r --arg u "$url" '[.[] | select(.config.url == $u)] | length')
[ "$dupe" = "0" ] ||
    die "a hook on $REPO already points at that payload URL -- nothing to create.
  To change its secret instead, see docs/secrets.md (rotation is portal-first)."

# --- create --------------------------------------------------------------
# Secret: pass -> pipe -> jq -> pipe -> gh. Never in argv, never on screen,
# never in a temporary file. jq -Rs also does the JSON escaping that manual
# quoting gets wrong. The URL goes via --arg: it is not a credential.

pass show "$PASS_SECRET" | head -n 1 | tr -d '\n' |
jq -Rs --arg url "$url" '
    { name: "web",
      active: true,
      events: ["push"],
      config: { url: $url,
                content_type: "json",
                insecure_ssl: "0",
                secret: . } }' |
gh api -X POST "repos/$REPO/hooks" --input - --jq \
    '"created hook \(.id)  active=\(.active)  events=\(.events | join(","))"' ||
    die "create failed -- the body above is the only thing that changed from the
  attempt that returned 400, so a parse error here means jq, not the shell."

# --- verify --------------------------------------------------------------
# A hook that exists is not a hook that works: the create call says nothing
# about whether the far end accepts the signature.

id=$(gh api "repos/$REPO/hooks" | jq -r --arg u "$url" '.[] | select(.config.url == $u) | .id')
[ -n "$id" ] || die "created, but cannot find the hook again to verify it"

gh api -X POST "repos/$REPO/hooks/$id/pings" >/dev/null || die "ping failed"

n=0
delivery=""
while [ "$n" -lt 12 ]; do
    delivery=$(gh api "repos/$REPO/hooks/$id/deliveries" --jq \
        '.[0] | "\(.event) status=\(.status) code=\(.status_code) at=\(.delivered_at)"' 2>/dev/null) || delivery=""
    case $delivery in
        ping*) break ;;
    esac
    n=$((n + 1))
    sleep 1
done

printf 'hook %s  %s\n' "$id" "${delivery:-no delivery recorded after 12s}"

case $delivery in
    *code=2*)
        echo "OK: the directory accepted a signed delivery." ;;
    *code=40*)
        echo "REJECTED: the stored secret and the portal's disagree." >&2
        echo "  Rotate from the portal; see docs/secrets.md." >&2
        exit 1 ;;
    *)
        echo "inconclusive -- check: gh api repos/$REPO/hooks/$id/deliveries" >&2
        exit 1 ;;
esac
