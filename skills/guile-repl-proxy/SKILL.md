---
name: guile-repl-proxy
description: Record everything that passes through a Guile socket REPL by routing it via a logging proxy on PORT+1, with per-project rotated transcripts, and connect Emacs with Geiser through the same proxy. Use when you need a reviewable history of what was evaluated, when debugging why a REPL session behaved oddly, or when a human and an agent should share one traced session.
allowed-tools: Bash, Read
metadata:
  requires:
    binaries: [guile3, nc]
    binaries-fallback: [guile]
    optional-binaries: [sockstat, lsof, pgrep]
    process: >-
      runs a long-lived listener; needs pgrep/pkill to find and clear a stale
      one, which is the failure it most often diagnoses
    ports: binds 127.0.0.1:PORT+1, connects to 127.0.0.1:PORT
    filesystem:
      - ~/.guile-skill/projects/<slug>/repl.log  (rw; rotated at 4 MiB, 5 generations)
    network:
      - 127.0.0.1 only
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

# A transcript of what was actually evaluated

`guile3 --listen=PORT` gives you a REPL; nothing records what went through it.
The proxy sits on `PORT+1`, forwards bytes verbatim, and tees a timestamped
transcript. Connect to `PORT+1` and the session is recorded; connect to `PORT`
and it is not.

```
agent / Emacs ──▶ 127.0.0.1:PORT+1 (proxy) ──▶ 127.0.0.1:PORT (guile3 --debug --listen)
                          │
                          └──▶ ~/.guile-skill/projects/<slug>/repl.log
```

## Where transcripts go

Keyed on the working directory exactly as `~/.claude/projects/` is — every `/`
and `.` becomes `-`:

```
/home/dsp-dr/ghq/github.com/dsp-dr/guile-skills
  -> ~/.guile-skill/projects/-home-dsp-dr-ghq-github-com-dsp-dr-guile-skills/repl.log
```

Rotated at 4 MiB, five generations, rotated between connections so no session is
cut in half. **Outside the repository on purpose**: a transcript contains
whatever was evaluated and must never become commit-adjacent.

Transcript format — `->` is toward the REPL, `<-` is back:

```
;; connection 2 at 2026-09-26T16:59:16Z
-> 12:59:16.322 ,trace (fib 3)
<- 12:59:16.349 trace: |  (fib 3)
<- 12:59:16.349 trace: |  |  (fib 2)
-- 12:59:16.350 repl sent eof
```

## Emacs + Geiser through the proxy

Point Geiser at the proxy port and the human's session is recorded too, so an
agent reading the transcript can see what the person tried.

```elisp
;; M-x geiser-connect, host 127.0.0.1, port PORT+1
(setq geiser-guile-binary "guile3")   ; not `guile' — that may be 2.2.7
```

Geiser holds **one** connection open across many round-trips, unlike `nc -N`
which half-closes after each. Both work, but the proxy currently serves
connections **serially** — an agent and Geiser at the same time needs two proxies
or a threaded accept loop.

## Failure modes worth recognising

- **Empty transcript, no client output.** Almost always a stale proxy from an
  earlier session still holding the port: `pgrep -fl guile-repl-proxy`. The
  proxy now refuses to start with the errno instead of dying quietly, but an old
  one predating that fix will still be serving and writing to its own log.
- **`,trace` produces nothing.** The target REPL was started without `--debug`.
  No error is raised.
- **Non-UTF-8 chunks** are logged as `#<N non-utf8 bytes>` rather than corrupting
  the transcript; the bytes are still forwarded unchanged.
