Found it. Your evaluations are correct because they're actually reaching the
real REPL — but they aren't reaching it through the proxy process you think is
recording them, so the transcript you're checking never sees them.

## What was actually running

```
$ pgrep -fla guile-repl-proxy
73825 guile3 ./bin/guile-repl-proxy.scm --listen 42222 --target 42221 --log
  .../guile-repl-proxy-bench/e2-with/projects/-stale-slug/old-repl.log
```

That's a proxy from an earlier session: it's listening on the right port
(42222 -> 42221, matching this project's ports), so nc/geiser/eval scripts
connect to it without any error, and it forwards bytes to the real REPL on
42221 without any error. But it was started with `--log` pointed at
`projects/-stale-slug/old-repl.log` — a leftover path from whatever session
launched it — not at this project's transcript path,
`projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log`.

The file you're comparing to "yesterday" is the second one:

```
$ ls -la projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
-rw-r--r-- 1 jwalsh wheel 117 "Sep 26 17:25:41 2026" repl.log
$ md5sum repl.log
750cbac985fc1ce573ab342f556255ce  repl.log
```

117 bytes, last modified Sep 26 — that's "yesterday," and its content is one
old `(+ 1 1)` connection. It genuinely hasn't changed, because nothing has
written to it since.

## Proof

I sent an eval through the proxy port and watched both files:

```
$ ./bin/guile-repl-eval.sh '(+ 20 22)'
$3 = 42
```

Correct answer. But:

- `repl.log` (the one you'd check) — md5sum unchanged, still `750cbac9...`,
  still 117 bytes.
- `projects/-stale-slug/old-repl.log` grew a new `connection 3` block ending
  in `$3 = 42`, timestamped just now.

So every "correct" evaluation you've run has been landing in
`-stale-slug/old-repl.log`, not in the transcript you're diffing. That file
is byte-for-byte identical to yesterday because it is, quite simply, dead —
no process has appended to it since yesterday's last connection.

This is the exact failure mode the guile-repl-proxy skill calls out: *"Empty
transcript, no client output. Almost always a stale proxy from an earlier
session still holding the port."* In your case the transcript isn't empty,
just frozen — same root cause, a stale proxy squatting on the port with a
log path from whoever started it.

## Fix applied

I killed only the stale proxy (left the REPL on 42221 untouched, since it was
correctly configured and had no problem) and started a fresh proxy with the
correct `--log` target:

```
$ pkill -f "guile-repl-proxy.scm --listen 42222"
$ ./bin/guile-repl-proxy.scm --listen 42222 --target 42221 \
    --log .../projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log &
```

Verified:

```
$ ./bin/guile-repl-eval.sh '(* 7 6)'
$4 = 42
$ md5sum repl.log
27531072271cf73448152b30e100e173  repl.log   # changed
```

The transcript now has a new session header and the `(* 7 6)` round-trip in
it. Evaluations were never silently failing — they were being logged, just
to the wrong file, because the live proxy's `--log` flag was set once at
process start and never revisited when the project (or the session that
started it) moved on.

## Takeaway

`guile-repl-server.sh --status` reports the port state (listening/down) but
not what log path a *running* proxy was actually launched with — so "proxy
is up" and "proxy is logging where I expect" are different facts, and only
the second one is what a byte-for-byte-transcript check is really asking.
When a transcript looks stale despite correct answers, don't trust
`pgrep`/`--status` alone — check the actual `--log` argument in the running
proxy's command line (`ps`/`pgrep -fla`) against the path `guile-repl-paths.sh`
computes for your current `GUILE_REPL_ROOT`/cwd. If they don't match, kill
that one proxy and restart it with the right log path (no need to touch the
REPL itself).
