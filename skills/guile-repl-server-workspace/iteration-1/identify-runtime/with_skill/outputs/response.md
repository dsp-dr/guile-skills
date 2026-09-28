# Which Guile runs your code, and what the REPL surface is started with

## Machine

```
$ uname -a; whoami; hostname -s
FreeBSD nexus 15.1-RELEASE FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC amd64
jwalsh
nexus
```

This is FreeBSD, which matters: on FreeBSD `guile` and `guile3` are often
**different versions**.

## Which binary actually runs

```
$ for b in guile guile3 guile-3.0; do
    command -v $b >/dev/null 2>&1 && printf '%-10s %s\n' "$b" "$($b --version | head -1)"
  done
guile      guile (GNU Guile) 2.2.7
guile3     guile (GNU Guile) 3.0.10
guile-3.0  guile (GNU Guile) 3.0.10
```

So bare `guile` on this machine is **2.2.7** (`guile2-2.2.7_6` in `pkg`), while
`guile3` and `guile-3.0` are the same **3.0.10** binary (`/usr/local/bin/guile3`
is a symlink/copy that resolves alongside `/usr/local/bin/guile-3.0`, from the
`guile3-3.0.10` package). The `guile-repl-server` skill's helper script
(`bin/guile-repl-paths.sh`) picks `guile3` whenever it's present:

```sh
if command -v guile3 >/dev/null 2>&1; then
    GUILE=${GUILE:-guile3}
else
    GUILE=${GUILE:-guile}
fi
```

Confirmed by running it: `guile /usr/local/bin/guile3` is what it selects.

**Bottom line: your code runs on Guile 3.0.10, via the `guile3` binary — not
the bare `guile` on PATH, which is 2.2.7.** Anything that shells out to plain
`guile` on this box would silently run on the older interpreter.

## What the REPL surface is actually started with

The project's REPL scripts live in `bin/` (`guile-repl-paths.sh`,
`guile-repl-server.sh`, `guile-repl-proxy.scm`), documented by the
`guile-repl-server` skill (`skills/guile-repl-server/SKILL.md`).

For this session the port/log root were pinned (to avoid colliding with other
concurrent sessions in this same repo checkout) via:

```
GUILE_REPL_PORT=42301
GUILE_REPL_ROOT=/tmp/claude-1001/.../guile-repl-server-bench/e1-with
```

Running `./bin/guile-repl-paths.sh` with those exported reports:

```
slug        -home-jwalsh-ghq-github-com-dsp-dr-guile-skills
log dir     .../projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills
repl port   42301
proxy port  42302  (repl port + 1)
guile       /usr/local/bin/guile3
```

(Normally, with no override, the port is derived deterministically from the
absolute working-directory path: `37000 + cksum(slug) mod 900`, so a given
project always lands on the same port.)

Before starting anything, `--status` confirmed no stale listener was already
on this port (a stale listener "looks exactly like a broken new one" per the
skill, so it's checked first):

```
$ ./bin/guile-repl-server.sh --status
repl   42301  down
proxy  42302  down
```

Then `./bin/guile-repl-server.sh` started it, and the process table
confirms exactly what was launched:

```
$ ./bin/guile-repl-server.sh
repl   42301  (guile3 --debug, load path: src)
proxy  42302  -> 42301, logging to .../repl.log
eval with: ./bin/guile-repl-eval.sh '(+ 1 1)'

$ ps aux | grep guile3
jwalsh  9154  guile3 --debug --listen=42301 -c (sleep 86400) (guile-3.0)
jwalsh  9180  guile3 ./bin/guile-repl-proxy.scm --listen 42302 --target 42301 \
              --log .../repl.log (guile-3.0)
```

So concretely, two processes are started:

1. **The REPL itself**: `guile3 --debug --listen=42301 -c '(sleep 86400)'`
   - `--debug` is load-bearing, not cosmetic: without it Guile starts the
     fast VM engine and tracing/breakpoint meta-commands (e.g. `,trace`)
     silently do nothing — no output, no error — which reads as "this
     procedure makes no calls" when it's really "the debug surfaces are
     off." Every start path in this skill passes `--debug`.
   - `--listen=42301` binds a socket REPL on `127.0.0.1:42301` only (never
     `0.0.0.0` — a socket REPL is unauthenticated arbitrary code execution).
   - `-c '(sleep 86400)'` is just a no-op main form to keep the process alive
     as a daemon; the real interaction happens over the socket.
   - There's no `-L src` in the actual command line here because this repo
     has no `src/` directory at its root (`bin/guile-repl-server.sh` only
     adds `-L $SRC_DIR` when that directory exists); on a project that does
     have `src/`, the REPL's load path would include it.

2. **A logging proxy**: `guile3 bin/guile-repl-proxy.scm --listen 42302
   --target 42301 --log <dir>/repl.log` — sits on `PORT+1` (42302), forwards
   to the real REPL on 42301, and transcribes the conversation to
   `repl.log` in the per-project log directory under `GUILE_REPL_ROOT`
   (normally `~/.guile-skill/projects/<slug>/`, here redirected to the
   scratch root above since this is a parallel benchmark run). Both bind
   loopback only.

After confirming this, per the task's cleanup instructions, I stopped both
processes:

```
pkill -f "listen=42301"
pkill -f "guile-repl-proxy.scm --listen 42302"
```

## Summary

- Your code will run on **Guile 3.0.10** via the `guile3` binary — bare
  `guile` on this FreeBSD box is the older 2.2.7 and would give
  different/broken behavior.
- The REPL surface is started as `guile3 --debug --listen=<port> -c '(sleep
  86400)'`, bound to `127.0.0.1` only, with `--debug` required for tracing to
  work at all, plus a companion `guile-repl-proxy.scm` process one port
  higher that forwards traffic and logs the transcript to `repl.log`.
