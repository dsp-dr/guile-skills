# Diagnosis: REPL process died, proxy kept the port warm and masked it

## tl;dr

The Guile REPL process on port 42341 had **crashed shortly after startup**.
The logging proxy on 42342 was still alive and correctly listening, but every
connection through it hit a dead target. That's why `guile-repl-eval.sh`
returned nothing and *felt* like the transcript wasn't moving: the only thing
being appended for each attempt was a one-line connection-refused error, not
a real evaluation.

I did not change any code. I stopped the wedged pair and started a clean one
with the same script you already used, and it now works end-to-end.

## What I checked, in order (per the skill's own rule: `--status` before
`--stop` before debugging anything else)

1. Ran `./bin/guile-repl-server.sh --status`:

   ```
   repl   42341  down
   proxy  42342  listening
   log    .../projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
   ```

   That's the whole bug in two lines: the REPL is down, but the proxy in
   front of it is still up.

2. Confirmed at the process level — no `guile3 ... --listen=42341` process
   exists at all, only the proxy targeting it:

   ```
   jwalsh 3559 ... guile3 ./bin/guile-repl-proxy.scm --listen 42342 --target 42341 --log .../repl.log
   ```

3. Read `repl.stderr` for the dead REPL process:

   ```
   In thread:
   Wrong type to apply: ()
   ```

   An uncaught error in the REPL's connection-handling thread took the whole
   `guile3 --debug --listen=42341 -c '(sleep 86400)'` process down with it.

4. Read `repl.log` (the transcript the skill points at). The most recent
   session shows exactly the crash-then-mask sequence:

   ```
   ;; session 2026-09-28T03:34:04Z  proxy 42342 -> repl 42341
   ;; connection 1 at 2026-09-28T03:34:05Z
   -> 23:34:05.280 (+ 1 1)
   ...
   <- 23:34:05.312 $1 = 2
   -- 23:34:05.312 repl sent eof
   ;; connection 2 at 2026-09-28T03:34:06Z
   !! 23:34:06.395 cannot reach repl on 42341: (system-error "connect" "~A" ("Connection refused") (61))
   ```

   One eval succeeded (that's the "success lines" you saw at startup — the
   server's own startup handshake), and by the very next connection a second
   later the REPL was already gone. Everything after that is
   `cannot reach repl on 42341: ... Connection refused`, repeated.

5. Reproduced your exact symptom live, before touching anything: ran
   `./bin/guile-repl-eval.sh '(+ 1 1)'` myself against the still-broken pair.
   It printed:

   ```
   guile-repl-eval: no reply from 127.0.0.1:42342
   ```
   (exit code 1) — nothing useful on stdout, which matches "gives me nothing
   back." And a new line *was* appended to the transcript (a third
   `cannot reach repl` entry) — it wasn't literally frozen, it just wasn't
   growing with anything that looked like your eval succeeding, which reads
   the same as "hasn't grown" if you're eyeballing it for real output.

## Root cause

The REPL (port 42341) died from an unhandled exception in its own connection
thread (`Wrong type to apply: ()`) right after serving one connection. The
proxy (port 42342) has no way to know its target died — it just keeps
listening and reports "connection refused" to the log on each attempt. So
you had a live, listening, seemingly-fine proxy in front of a corpse, which
is indistinguishable from the outside from "everything is fine but slow"
until you check `--status` for both ports, not just one.

## Fix applied

No code changes — this was an operational problem, not a code bug. Per the
skill's "stale listener" guidance, I stopped both processes and started a
clean pair with the same script:

```
$ ./bin/guile-repl-server.sh --stop
stopped proxy on 42342
$ ./bin/guile-repl-server.sh --status
repl   42341  down
proxy  42342  down
$ ./bin/guile-repl-server.sh
repl   42341  (guile3 --debug, load path: src)
proxy  42342  -> 42341, logging to .../repl.log
```

Verified it actually works now:

```
$ ./bin/guile-repl-eval.sh '(+ 1 1)'
$1 = 2
$ ./bin/guile-repl-eval.sh '(* 6 7)'
$2 = 42
$ ./bin/guile-repl-server.sh --status
repl   42341  listening
proxy  42342  listening
```

And the transcript grows with real evaluation output for each call now (log
line count went from 76 to 91 lines after just the first eval, including the
full Guile banner and `$1 = 2`).

## State I'm leaving things in

Both the REPL (42341) and the logging proxy (42342) are up and healthy right
now, having just served two successful evaluations. I did not stop them
afterward — a working, freshly-verified server pair is the natural resting
state of this fix. If you want it torn down, `./bin/guile-repl-server.sh
--stop`.

## Suggestion (not applied, since you asked me not to change code first)

The proxy silently swallowing "target died" as a per-connection log line is
what let this go unnoticed. If this keeps happening, the proxy could refuse
to accept new client connections (or emit a clearer client-facing error
instead of just closing/timing out) once it sees `Connection refused` from
its target, rather than relying on someone noticing `--status` shows two
different states for the pair. That's a proxy behavior change, so I'm
flagging it rather than making it.
