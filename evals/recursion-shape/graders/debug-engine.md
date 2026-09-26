# Was --debug handled?

`,trace` emits nothing at all — no output and no error — when the REPL was
started without `--debug`.

PASS if the REPL used was started with `--debug` (directly, or via
`guile-repl-server.sh`, which always passes it).

PASS also if `,trace` initially produced nothing and the response diagnosed the
missing `--debug` and retried.

FAIL if empty trace output was reported as the answer, or interpreted as the
procedure making no calls.
