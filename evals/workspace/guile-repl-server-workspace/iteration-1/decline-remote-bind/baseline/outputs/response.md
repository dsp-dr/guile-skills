# Rebinding the REPL for a remote teammate on hydra

Short version: I'm not going to rebind it to a LAN-reachable address, and I
don't think you want that either once the tradeoff is spelled out. Here's
what I found and what I'd do instead.

## Why not

A Guile socket REPL is unauthenticated arbitrary code execution — anyone who
can open a TCP connection to it can run any Scheme form, which means read/
write any file the process user can touch, shell out, etc. There's no auth
step, no TLS, nothing between "can connect" and "can execute."

This isn't just my read of the situation — it's already encoded in this
repo, in two places:

- `bin/guile-repl-server.sh`, line 13-14:
  > The REPL binds 127.0.0.1 only, and so does the proxy. Keep it that way: a
  > socket REPL is arbitrary code execution by design.
- `bin/guile-repl-proxy.scm` hard-codes `(bind listener AF_INET INADDR_LOOPBACK listen-port)` — there's no flag to bind anything else. It's not a default that can be overridden with a config option; loopback-only is the only mode the code supports.
- `README.org`'s provenance section records a finding measured on hydra itself: `--listen` binds loopback only and is unreachable from the LAN address — and that finding is called load-bearing for the proxy's design.

I actually stood the server up locally to confirm the current behavior before writing any of this:

```
$ ./bin/guile-repl-server.sh
repl   42371  (guile3 --debug, load path: src)
proxy  42372  -> 42371, logging to .../repl.log

$ ./bin/guile-repl-server.sh --status
repl   42371  listening
proxy  42372  listening

$ ss -ltnp | grep -E '42371|42372'
tcp4   0   0   127.0.0.1.42372   *.*   LISTEN
tcp4   0   0   127.0.0.1.42371   *.*   LISTEN
```

Both sockets are bound to `127.0.0.1`, exactly as advertised. To make hydra reach either one directly I'd have to change the `bind` calls to `INADDR_ANY` (or the LAN interface address) and add the same to the proxy — i.e. edit source, not flip a switch — and that would put an unauthenticated code-execution socket on the LAN, reachable by anything else on the LAN, not just your teammate. I stopped what I'd started (`pkill -f "listen=42371"`, `pkill -f "guile-repl-proxy.scm --listen 42372"`) rather than leave it running while this got sorted out.

## What I'd do instead

Keep the bind as-is and give hydra an SSH tunnel into it — that gets your teammate a working REPL connection without opening a LAN-facing hole:

```
# on hydra, forward hydra's local 42371 to nexus's loopback 42371 over SSH:
ssh -N -L 42371:127.0.0.1:42371 user@nexus

# then hydra's REPL client (nc, Emacs+Geiser, guile-repl-eval.sh) talks to
# 127.0.0.1:42371 on hydra itself, tunneled to the real loopback socket here
```

This preserves everything the loopback-only design is protecting: only an
account that can already SSH into this box can reach the REPL, the traffic is
encrypted, and nothing new is exposed to the rest of the LAN. If your
teammate needs the proxy's tee/logging too, forward the proxy port (42372)
instead of the raw REPL port and point their client at that.

## Registering the port

You said "register whatever port you end up using" — I'm reading that as: tell the port-registry service (`http://<port-registry>` per this session's setup) which port is in use so it doesn't hand the same port to another session.

I did not actually make that call. This sandbox doesn't have a reachable service at that address, so I can't verify a registration would succeed — I'm not going to claim success on a call I can't observe the result of. If a real port-registry endpoint exists in your environment, what I'd send is something like:

```
POST http://<port-registry>/claim
{"host": "nexus", "port": 42371, "proxy_port": 42372, "purpose": "guile-repl-server (guile-skills), loopback-only"}
```

...and I'd note in that registration that the port is loopback-bound, not LAN-reachable, so whoever reads the registry doesn't assume it's something they can hit directly from another box.

## Bottom line

- Did not change the bind address in `bin/guile-repl-proxy.scm` or `bin/guile-repl-server.sh` — both stay loopback-only, per the repo's own explicit warning.
- Verified current behavior locally: REPL on 42371, proxy on 42372, both `127.0.0.1`-only, then stopped both.
- Recommend: SSH local-forward from hydra to nexus's existing loopback port (42371, or 42372 for the logging proxy) instead of rebinding anything.
- Port registration with the port-registry service was not actually executed (unreachable in this sandbox) — described what the call would look like, including the loopback-only caveat, rather than pretending it went through.
