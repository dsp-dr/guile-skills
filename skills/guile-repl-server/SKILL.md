---
name: guile-repl-server
description: Stand up a Guile project with a socket REPL an agent can drive - guile3 --debug --listen on a per-project port, with a logging proxy on PORT+1. Use when starting or resuming work on a Guile/Scheme project, when you need to evaluate code rather than only read it, or when a claim about Guile behaviour needs checking against a running interpreter.
license: MIT
allowed-tools: Bash, Read
metadata:
  requires:
    binaries: [guile3]
    binaries-fallback: [guile]
    optional-binaries: [sockstat, lsof, nc, pgrep]
    process: >-
      inspects and signals its own listeners (sockstat/lsof to find them,
      pkill to stop them); starts long-lived background processes
    ports: one TCP pair on 127.0.0.1, derived per project as 37000 + cksum(slug) mod 900
    filesystem:
      - ~/.guile-skill/projects/<slug>/  (rw; transcripts and stderr, outside the repo)
      - <project>/src  (r; Guile load path)
    network:
      - 127.0.0.1 only
      - http://192.168.86.29:4700  (portclaim; optional port registration)
    credentials: none
    danger: >-
      a Guile socket REPL is unauthenticated arbitrary code execution;
      bind 127.0.0.1 only, never 0.0.0.0 and never through a tunnel
  verified-on: FreeBSD 15.1-RELEASE, guile3 3.0.10, 2026-09-26
  enforcement: >-
      the requires block is documentation, not a sandbox: nothing in the harness
      reads it. Real gating is allowed-tools above, settings.json permissions,
      and `claude plugin eval --allow-tools` at eval time
---

# Start a Guile project with a REPL surface

The agent's hardest problems in a Lisp are **mechanical** (delimiters) and
**epistemic** (stale state, unverified claims), not stylistic. This skill is
about the epistemic half: having a running interpreter to check against, so
"this works" is a measurement rather than a guess.

## Get the runtime right first

On FreeBSD the binary is `guile3` (also `guile-3.0`); bare `guile` may be **2.2.7**.
Under Homebrew on macOS it is `guile`. A tool that shells out to `guile` and gets
2.2.7 fails in ways that look like your code is wrong.

```sh
uname -a; whoami; hostname -s        # which machine is this, really
for b in guile guile3 guile-3.0; do
    command -v $b >/dev/null 2>&1 && printf '%-10s %s\n' "$b" "$($b --version | head -1)"
done
```

Prefer `guile3` when it exists. `bin/guile-repl-paths.sh` does this and prints
its choice.

## Start it

```sh
./bin/guile-repl-server.sh          # REPL on PORT, logging proxy on PORT+1
./bin/guile-repl-server.sh --status # what is actually listening
./bin/guile-repl-server.sh --stop
```

The port is derived from the working directory, so a project always gets the
same one: `37000 + cksum(slug) mod 900`, where the slug is the absolute path with
every `/` and `.` replaced by `-`.

## Rules that are not negotiable

- **`--debug` or the debug surfaces silently do nothing.** Without it,
  `,trace (fib 4)` prints no lines *and raises no error* — which reads as "this
  procedure makes no calls". Every start path here passes `--debug`.
- **Bind loopback only.** A socket REPL is unauthenticated arbitrary code
  execution. Never `0.0.0.0`, never a tunnel you forget about.
- **Register the port.** This network runs *portclaim* at
  `http://192.168.86.29:4700`. `GET /ports/<port>` (404 means free), then
  `POST /claim` naming `node`, `repo`, `pwd`, `kind` and a `mandate` that states
  the exposure. Release with `DELETE /claim/<port>` on teardown.
- **A stale listener looks exactly like a broken new one.** Check before you
  start; `--status` before `--stop` before debugging anything else.

## Then

Evaluate with the `guile-repl-eval` skill. Read the transcript with
`guile-repl-proxy`.
