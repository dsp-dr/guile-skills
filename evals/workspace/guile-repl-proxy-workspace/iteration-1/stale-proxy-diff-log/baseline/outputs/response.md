Found it — you have a stale logging proxy from an earlier session still holding
port 42232, and it's writing to a *different log file* than the one you're
checking.

## What's actually running

`ps aux` on this host shows two separate processes involved in your REPL pair:

```
jwalsh 73791  guile3 --debug -L .../e2-base/src --listen=42231 -c (sleep 86400)
jwalsh 73836  guile3 ./bin/guile-repl-proxy.scm --listen 42232 --target 42231 \
              --log .../e2-base/projects/-stale-slug/old-repl.log
```

The REPL on 42231 is exactly what `bin/guile-repl-paths.sh` derives for this
project. But the proxy that's actually bound to 42232 (confirmed via `lsof
-iTCP:42232`, which shows PID 73836 owning it) is *not* logging to this
project's `repl.log`. It's logging to `.../projects/-stale-slug/old-repl.log`
— a log path from a different (older) invocation, started `Sun Sep 27 17:25:15
2026`.

`bin/guile-repl-server.sh --status` reports both ports "listening," which is
true and unhelpful: it only checks that something is bound, not which
process, and not where that process is writing its transcript.

## Proof: correct answer, wrong (unwritten) file

Before touching anything:

```
$ stat -f '%Sm %z bytes' .../projects/-home-jwalsh-.../repl.log
Sep 26 17:25:41 2026 117 bytes
$ stat -f '%Sm %z bytes' .../projects/-stale-slug/old-repl.log
Sep 27 17:25:22 2026 1266 bytes
```

Then I ran an eval through the normal path:

```
$ ./bin/guile-repl-eval.sh '(+ 100 23)'
$3 = 123
```

Correct answer. But afterward:

```
$ stat -f '%Sm %z bytes' .../projects/-home-jwalsh-.../repl.log
Sep 26 17:25:41 2026 117 bytes      <- unchanged, still yesterday's file
$ stat -f '%Sm %z bytes' .../projects/-stale-slug/old-repl.log
Sep 27 17:32:38 2026 1873 bytes     <- this is where your eval actually landed
```

`repl.log` (the file you're watching) is byte-for-byte what it was yesterday
because nothing has written to it since `2026-09-26T18:03:11Z`. Every
evaluation you've run today went through the live proxy on 42232, got
correctly forwarded to the REPL on 42231, and got a correct reply — the proxy
just recorded the transcript in `old-repl.log` under a stale project slug
directory instead.

## Why this happens (per `EXPERIMENTS.org` / the comments in
`guile-repl-proxy.scm`)

This is the documented "stale server" failure mode, one layer worse than the
usual case: normally a second proxy trying to bind an already-listening port
fails loudly (`SO_REUSEADDR` doesn't let two processes share a listen socket —
see the `bind` catch block in `guile-repl-proxy.scm`). Here the old proxy
process never died, so it's still perfectly healthy and answering every
connection — it just started with a `--log` path from whatever session
originally launched it (`-stale-slug/old-repl.log`), and nothing about a live
TCP connection tells it "the caller's cwd/slug is now different." A `--status`
or `--start` afterwards only checks "is a port bound," sees yes, and moves on;
it never checks *which log file the bound process is actually writing to*.

Net effect: evaluations are correct (the REPL and the proxy's byte-forwarding
are both working fine), but the transcript you're inspecting is inert because
the live proxy on that port is a leftover from a previous session, pinned to
its original `--log` argument.

## Fix

1. Confirm which process owns the proxy port and what `--log` it was started
   with:
   ```
   lsof -nP -iTCP:42232 -sTCP:LISTEN
   ps -o pid,lstart,args -p <pid>
   ```
2. Kill the stale proxy (it's PID 73836 in this session) — leave the REPL
   itself (73791) alone if you still want its state:
   ```
   kill 73836
   ```
3. Restart the proxy pointed at the correct log path for the current slug:
   ```
   ./bin/guile-repl-server.sh --no-proxy=0   # or just re-run guile-repl-server.sh;
                                              # it will see 42231 already listening
                                              # and only needs to (re)start the proxy
   ```
   or invoke `bin/guile-repl-proxy.scm` directly with `--target 42231 --log
   <project-dir>/repl.log`.
4. Going forward, don't trust `--status`'s "listening" as proof the transcript
   is live — cross-check with `lsof`/`ps` on the actual proxy PID and its
   `--log` argument, exactly as done above, whenever a transcript looks
   suspiciously idle.

Per your instructions, I have **not** killed anything on 42231/42232 in this
session — that stale proxy is left as-is for the orchestrator to clean up,
even though item 2 above is the concrete fix once you're ready to apply it.
