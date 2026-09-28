# guile-skills

Agent skills and tooling for working on Guile Scheme projects: stand up a
Guile socket REPL an agent can drive, evaluate code against it instead of
guessing, and record every evaluation through a logging proxy.

## What it does

This is a Claude Code plugin bundling three skills:

- **`guile-repl-server`** — starts a project's REPL (`guile3 --debug --listen`
  on a per-project port) plus a logging proxy on `PORT+1`. Use it when
  starting or resuming work on a Guile/Scheme project.
- **`guile-repl-eval`** — evaluates Scheme in that running REPL over its
  socket, with tracing, breakpoints, macro expansion, and profiling. Use it
  whenever a claim about Guile code should be checked by running it, not
  assumed.
- **`guile-repl-proxy`** — records everything that passes through the REPL
  via the logging proxy, with per-project rotated transcripts, and lets a
  human (via Emacs + Geiser) and an agent share one traced session.

## How to use it

Install the plugin, then in a Guile project's working directory ask Claude to
start the project's REPL, evaluate something, or check what a REPL session
actually returned — the matching skill loads automatically. The three skills
can also be driven directly from a shell via `bin/guile-repl-server.sh`,
`bin/guile-repl-eval.sh`, and `bin/guile-repl-proxy.scm`, or through the
Makefile (`gmake start`, `gmake eval F='(+ 1 1)'`, `gmake stop`).

## Setup

Requires `guile3` (or `guile` 3.x) and `nc` on the machine the REPL runs on;
`sockstat`/`lsof`/`pgrep` are used opportunistically for diagnostics if
present. No credentials, no network beyond `127.0.0.1`. See
[README.org](README.org) for the full design rationale, and
[EXPERIMENTS.org](EXPERIMENTS.org) for the failure modes this plugin exists
to catch. Data sent: none — everything stays on the machine running the REPL.
