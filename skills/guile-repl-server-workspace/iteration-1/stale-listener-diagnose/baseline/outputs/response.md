# Diagnosis: proxy was up, but the REPL behind it had died

## What was actually running

`./bin/guile-repl-server.sh --status` (with `GUILE_REPL_PORT=42351`,
`GUILE_REPL_ROOT=.../guile-repl-server-bench/e3-base`) reported:

```
repl   42351  down
proxy  42352  listening
log    .../projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
```

`ps aux | grep guile` confirmed it: there was a `guile-repl-proxy.scm --listen
42352 --target 42351 ...` process alive, but no `guile3 --debug --listen=42351`
process anywhere. The proxy — the thing your eval script actually talks to —
was fine. The REPL behind it was gone.

## Why the server said "success" and still ended up broken

The transcript log (`repl.log`) shows the REPL really did come up and really
did work, right after the server script printed its success lines:

```
;; session 2026-09-27T21:26:06Z  proxy 42352 -> repl 42351
;; connection 1 at 2026-09-27T21:26:07Z
-> 17:26:07.085 (+ 1 1)
-- 17:26:07.086 client sent eof
<- 17:26:07.087 GNU Guile 3.0.10
...
<- 17:26:07.116 Enter `,help' for help.
<- 17:26:07.116 $1 = 2
<- 17:26:07.116 
-- 17:26:07.116 repl sent eof
```

So the first eval a minute ago actually succeeded. But `repl.stderr` in that
same log directory had:

```
In thread:
Wrong type to apply: ()
```

The Guile process behind `--listen=42351` died after that first connection.
The proxy process didn't notice or die with it — it just kept listening on
42352, ready to accept new client connections, with nothing left on the other
end.

## What that produced for you just now

Reproducing your exact command against the still-listening proxy:

```
$ ./bin/guile-repl-eval.sh '(+ 1 1)'
guile-repl-eval: no reply from 127.0.0.1:42352
```

and the log picked up two more connection attempts instead of any eval output:

```
;; connection 2 at 2026-09-28T04:05:41Z
!! 00:05:41.193 cannot reach repl on 42351: (system-error "connect" "~A" ("Connection refused") (61))
;; connection 3 at 2026-09-28T04:06:03Z
!! 00:06:03.122 cannot reach repl on 42351: (system-error "connect" "~A" ("Connection refused") (61))
```

`guile-repl-proxy.scm`'s `serve` loop explains why you got silence instead of
an error you'd notice: when `connect` to the target REPL fails, it's caught,
logged to `repl.log` and to the proxy's own stderr, and then the client
connection is just closed — no bytes are ever written back to your client.
Your `nc` call completes with an empty reply, and `guile-repl-eval.sh` turns
that into `no reply from 127.0.0.1:42352` on stderr (easy to miss if you're
only watching for stdout). Meanwhile `repl.log` genuinely doesn't grow with
any `->`/`<-` transcript lines for these attempts, because the proxy never
got far enough to forward anything — only the `!! cannot reach repl` lines
were added, which reads exactly like "the transcript hasn't grown."

This is a stale-listener situation, just the opposite pairing from the usual
one: normally it's a stale REPL blocking a new server from binding. Here the
REPL died but the proxy in front of it kept running, so it looked alive from
the outside (port 42352 accepts connections fine) while forwarding to nothing.

## Fix applied (operational, no code changed)

Restarted the pair cleanly with the script's own stop/start:

```
$ ./bin/guile-repl-server.sh --stop
stopped proxy on 42352
$ ./bin/guile-repl-server.sh
repl   42351  (guile3 --debug, load path: src)
proxy  42352  -> 42351, logging to .../repl.log
eval with: ./bin/guile-repl-eval.sh '(+ 1 1)'
```

(Note `--stop` only reported killing the proxy — there was no repl process
left for its `pkill -f "listen=$GUILE_REPL_PORT"` to match, confirming the
REPL side was already dead before I touched anything.)

Verified twice after restart:

```
$ ./bin/guile-repl-eval.sh '(+ 1 1)'
$1 = 2
$ ./bin/guile-repl-eval.sh '(* 6 7)'
$2 = 42
$ ./bin/guile-repl-server.sh --status
repl   42351  listening
proxy  42352  listening
```

and `repl.log` now has real `->`/`<-` lines for both evaluations, so the
transcript is growing again.

## Current state I'm leaving things in

Both the REPL (`guile3 --debug --listen=42351`) and the proxy
(`guile-repl-proxy.scm --listen 42352 --target 42351`) are up and answering
evals correctly. I did not change any script or source file — this was a
process-state problem (a dead REPL process behind a still-listening proxy),
not a code bug, so the fix was stopping the orphaned proxy and starting a
fresh repl+proxy pair.

One loose end worth flagging, not fixed here since it needs no code change to
diagnose further: the `Wrong type to apply: ()` line reappeared in
`repl.stderr` immediately after the restart too, but this time the REPL
process survived it and kept answering (`$2 = 42` came through fine, and
`--status` still shows it listening). So that message on its own isn't fatal
— something else additionally killed the REPL process the first time. If it
recurs and takes the process down again, `repl.stderr` and `repl.log`'s `In
thread:` timing are the place to keep looking.
