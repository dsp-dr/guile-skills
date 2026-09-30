# Attaching Emacs + Geiser to this REPL while the agent keeps evaluating

For this benchmark session, the project's REPL/proxy ports were fixed (not
auto-derived from cwd) to avoid colliding with other concurrent sessions:

```
GUILE_REPL_PORT       = 42281   (guile3 --debug --listen, the real REPL)
GUILE_REPL_PROXY_PORT = 42282   (guile-repl-proxy.scm, repl port + 1)
GUILE_REPL_ROOT        = /tmp/claude-1001/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/bb12b06c-d22e-414d-bba1-89a46128a974/scratchpad/guile-repl-proxy-bench/e4-base
```

I confirmed both are up right now (`bin/guile-repl-server.sh --status` with
those env vars exported):

```
repl   42281  listening
proxy  42282  listening
log    <GUILE_REPL_ROOT>/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
```

## The one thing that will bite you here

`bin/guile-repl-proxy.scm` is a single-threaded `accept-loop`: it accepts one
client, pumps bytes for that connection until it fully closes, *then* calls
`accept` again for the next one. It does not fork or thread per connection.
Geiser opens one persistent connection and holds it open for the whole
editing session. My agent evaluations go through the proxy too, but as
short-lived connect → send → read → disconnect cycles (`guile-repl-eval.sh`
default target is the proxy port).

If Geiser connects to the **proxy** port (42282), the first side to connect
wins the proxy's single accept slot and the other is blocked/queued behind
it: once Geiser is attached, my next proxy-routed eval will hang until Geiser
disconnects, and vice versa. The underlying `guile3 --listen` REPL itself has
no such limit — it's designed to serve multiple independent connections, each
with its own module/binding state — so the constraint is specific to this
proxy's accept loop, not the REPL.

## What to actually do

**Attach Geiser directly to the REPL port (42281), not the proxy.** That
gives you a genuinely concurrent session alongside the agent's proxy-routed
evals, with no blocking in either direction:

In Emacs:

```
M-x geiser-connect RET
Scheme implementation: guile RET
Host: 127.0.0.1 RET
Port: 42281 RET
```

(or non-interactively: `(geiser-connect 'guile "127.0.0.1" 42281)`)

Trade-off: whatever you evaluate from that Geiser buffer will **not** show up
in the transcript log (`repl.log`), because only traffic that passes through
the proxy gets tee'd and timestamped. Only the agent's proxy-routed
evaluations are logged. Both sides do share the same live Guile process and
the same top-level bindings/state (defining something in one is visible from
the other), since it's the same interpreter — only the connection paths (and
therefore the logging) differ.

If you want Geiser's session logged too, run a second proxy instance in
front of the same REPL, on its own port, instead of sharing 42282:

```sh
GUILE_REPL_ROOT=/tmp/claude-1001/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/bb12b06c-d22e-414d-bba1-89a46128a974/scratchpad/guile-repl-proxy-bench/e4-base
./bin/guile-repl-proxy.scm \
  --listen 42283 \
  --target 42281 \
  --log "$GUILE_REPL_ROOT/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/geiser.log"
```

Then `M-x geiser-connect` to `127.0.0.1` port `42283`. This keeps a separate,
Geiser-only transcript (`geiser.log`) without contending with the agent's
existing proxy on 42282 — each proxy still only serves one connection at a
time, but now each has exactly one long-lived client.

## Summary of concrete values for this session

| What | Value |
|---|---|
| REPL port (attach Geiser here) | `42281` |
| Proxy port (agent uses this; avoid for Geiser) | `42282` |
| Optional second proxy port for a logged Geiser session | `42283` (not yet running — start it if you want this) |
| Host | `127.0.0.1` (loopback only, by design — a socket REPL is unauthenticated code execution) |
| Transcript log (agent's proxy-routed evals) | `<GUILE_REPL_ROOT>/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log` |
| Guile in use | `guile3` (`/usr/local/bin/guile3`), started with `--debug` so tracing meta-commands (`,trace`, `,break`) work from Geiser too |
