---
type: llm
focus: trace
---

# Was a stale listener considered and checked?

The dominant cause is a proxy left running from an earlier session: it holds the
port, the new proxy's bind fails, and the old one keeps serving while writing to
its own log file — so the log being read is not the log being written.

PASS if the response inspects actual process or socket state — `pgrep -fl
repl-proxy`, `sockstat -4 -l`, `lsof -nP -iTCP:<port> -sTCP:LISTEN`, or
`guile-repl-server.sh --status` — rather than only reasoning about causes.

PASS if it also names the second possibility (a REPL started without `--debug`,
so `,trace` produced nothing) — but state inspection is required either way.

FAIL if it proposes a list of possible causes with no command that would
distinguish them.

FAIL if it suggests deleting the log or restarting blindly as the first step.
