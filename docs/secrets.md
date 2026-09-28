# Secrets

This repo has no secrets in it, and should never acquire any. Everything lives in
`pass` on the machine that administers the plugin directory registration.

## Inventory

| `pass` entry | What it is |
|---|---|
| `github/dsp-dr/guile-skills/directory-webhook-secret` | Shared secret the directory's sender signs push deliveries with; GitHub verifies the signature against it. |
| `github/dsp-dr/guile-skills/directory-webhook-url` | Payload URL for the same webhook. |

**The URL is stored as a secret too, deliberately.** It is not a credential — a
request to it still fails signature verification without the secret — but it
embeds a portal-issued UUID that identifies this plugin's ingest endpoint, and
this repo is public. Treating it as public config and the secret as private
would mean two handling rules for two halves of one thing, which is how the
wrong half ends up pasted into an issue. One rule: both are `pass` entries,
neither is ever committed, neither is ever pasted anywhere public.

## Properties of this particular store that change the process

Measured on nexus, 2026-09-28 — not assumed:

- **The store is not git-backed.** `~/.password-store` is not a git repo, so
  there is no `pass git log`, no history, and **no undo**: `pass insert -f`
  overwrites irrecoverably.
- **It therefore does not sync.** These entries exist on nexus only. hydra, the
  mac and the pi cannot read them.
- **One GPG recipient.** Only that key decrypts; adding a second machine means
  adding a recipient and re-encrypting the store, not copying the `.gpg` file.
  Which key: `cat "${PASSWORD_STORE_DIR:-$HOME/.password-store}/.gpg-id"`.
- **`pass -c` needs a reachable X display.** `xclip` is installed; `xsel`,
  `wl-copy` and `pbcopy` are not. Over SSH it works only while X11 forwarding is
  up — check with `echo "$DISPLAY"` — and the clipboard it lands in belongs to the
  machine running the X server, not to nexus.

## Reading without disclosing

Never `cat`, `echo`, or `pass show` a secret into a terminal that is being
recorded — which includes any shell an agent is driving, and includes this
repo's own REPL transcripts. To confirm an entry is present and non-empty:

```sh
pass ls github/dsp-dr/guile-skills                    # names only
pass show github/dsp-dr/guile-skills/directory-webhook-secret | wc -c   # length only
```

To get a value into a browser form, put it on the clipboard rather than on the
screen; `pass` clears it after 45 seconds:

```sh
pass -c github/dsp-dr/guile-skills/directory-webhook-secret
```

## Storing or replacing a value

```sh
pass insert -f github/dsp-dr/guile-skills/directory-webhook-secret
pass insert -f github/dsp-dr/guile-skills/directory-webhook-url
```

`insert` prompts with echo off and asks for confirmation; `-f` skips the
"overwrite?" question. Use `pass edit` instead if the entry should carry notes
below the value — `pass` convention is value on line 1, notes after.

`pass generate` does **not** apply to either entry. Both values are issued by the
directory portal; a locally generated one would simply fail verification.

## First-time setup of the webhook

**Done: created on `dsp-dr/guile-skills` 2026-09-28, ping delivered `200`.**
Recorded because "the portal gave me a URL" and "GitHub is sending deliveries"
are different states and only the second one matters. The hook's id is not
written down here — it changes if the hook is ever recreated, so read it back
instead:

```sh
gh api repos/dsp-dr/guile-skills/hooks \
    --jq '.[] | {id, active, events, secret: (if .config.secret then "set" else "NOT SET" end)}'
```

Store both values in `pass`, then run the installer:

```sh
pass insert -e github/dsp-dr/guile-skills/directory-webhook-url
pass insert    github/dsp-dr/guile-skills/directory-webhook-secret
scripts/install-directory-webhook.sh
```

It takes no arguments, refuses to create a second hook for a payload URL that
already has one, and ends by pinging the hook and reporting the delivery status
code — because a hook that exists is not a hook that works. `code=2xx` is the
only evidence both sides agree.

### Traps met getting there

Both present as something other than what they are, which is why they are
written down rather than remembered:

- **Do not build the JSON body with a here-document.** `<<EOF` requires its
  terminator at column zero. An indented `EOF` is invisible in a terminal, never
  matches, puts the terminator line *inside* the body, and GitHub answers
  `Problems parsing JSON` — which reads as a malformed payload rather than a
  shell quoting fault. `<<-EOF` does not save you: it strips tabs, not spaces.
  The installer uses `jq` to build the body for exactly this reason, and takes no
  arguments so there is nothing left to quote wrong.
- **`gh` may advise `needs the "admin:repo_hook" scope`. On a `repo`-scoped
  token that advice is wrong**, and following it broadens the token for nothing.
  The create endpoint's `X-Accepted-Oauth-Scopes` includes `repo`. Probe before
  re-authenticating — an empty body cannot create anything, so it is free:

  ```sh
  printf '{}' | gh api -X POST repos/dsp-dr/guile-skills/hooks --input - -i
  ```

  **422** means the token is sufficient and the body was the problem; **403**
  means the scope really is missing.

## Rotating the webhook secret

Portal-first, always. The secret cannot be chosen locally, so the portal's copy
is the authority and everything else is catching up to it.

1. **Directory portal** → this plugin → webhook → regenerate the secret. Copy it
   before leaving the page; it is displayed once.
2. **Store it**, overwriting in place:
   ```sh
   pass insert -f github/dsp-dr/guile-skills/directory-webhook-secret
   ```
   Overwriting is correct here rather than careless: the previous secret stopped
   being valid the moment the portal regenerated, so there is nothing worth
   keeping. If the paste was wrong, the fix is to regenerate again at step 1 —
   not to recover the old value.
3. **Update GitHub**: Settings → Webhooks → this hook → Secret, paste, Update.
   Get it there with `pass -c` rather than reading it aloud on screen. The field
   never displays the stored value, so there is nothing to compare against — a
   re-paste is the only way to be sure.
4. **Prove it took**: the hook's Recent Deliveries tab → Redeliver on the most
   recent delivery, or push a trivial commit. A 2xx is the only evidence that
   both sides agree.
5. **A 401 or 403 means the two copies disagree.** Go back to step 1 rather than
   guessing which side is stale — you cannot read either stored value back to
   compare them.

A delivery that returns 2xx with **no** secret configured looks identical to a
correctly signed one in the deliveries list. So after any change, confirm the
Secret field still shows as set; an empty secret is the silent failure here.

## Teardown

Deleting the GitHub hook alone leaves the portal believing it is still
subscribed. All three steps, in this order:

```sh
pass rm github/dsp-dr/guile-skills/directory-webhook-secret
pass rm github/dsp-dr/guile-skills/directory-webhook-url
```

...then delete the webhook under Settings → Webhooks, then unsubscribe the
webhook in the directory portal.

## Replicating a secret into GitHub Actions

Some secrets need a copy on GitHub so a workflow can use one. `pass` stays the
source of truth; GitHub is a replica, and values move one way only:

```sh
scripts/sync-secrets.sh status        # manifest vs. what GitHub actually holds
scripts/sync-secrets.sh push          # set every manifest entry from pass
scripts/sync-secrets.sh push NAME     # just one
scripts/sync-secrets.sh remove NAME   # delete one from GitHub (asks first)
```

The mapping lives in [`scripts/secrets.map`](../scripts/secrets.map) — GitHub secret
name, `pass` entry, and which application (`actions`, `dependabot`,
`codespaces`). Names only, no values, which is why it is committed.

**It is currently empty, and that is the correct state.** `gate.yml` and
`labeler.yml` run on the automatic `GITHUB_TOKEN`; this repo needs no secret of
its own yet.

Two things about this direction of travel:

- **GitHub never returns a secret's value.** `status` can therefore compare
  presence and `updatedAt` and nothing else — it cannot tell you the replica
  still matches `pass`. When in doubt, re-push; setting a secret to the value it
  already has costs nothing.
- **The webhook secret does not go here.** GitHub already holds its own copy in
  the webhook config, no workflow consumes it, and a third copy in Actions is
  somewhere a workflow could accidentally print. The rule is one replica per
  actual consumer, not one replica per available store.

## What is scripted, and what is not

- **Creation is scripted** — `scripts/install-directory-webhook.sh`. Typing it at a
  prompt failed twice on shell quoting before the script existed, which is the
  argument for a file: the fragile part is the JSON body, and a script removes
  every expansion from it.
- **Rotation is not, and should not be.** The secret cannot be chosen locally —
  the portal issues it and shows it once — so rotation always begins with a
  browser and a copy. A script could only accept the value and forward it, which
  adds a local-secret-to-network step while removing no judgement. The runbook
  above is the whole of it.

Both hold the same line on handling: values live in `pass`, reach `gh` on a pipe,
and never become a process argument, appear on screen, or land in a file.
