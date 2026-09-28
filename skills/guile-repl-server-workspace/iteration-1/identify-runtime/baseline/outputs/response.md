# Which Guile runs your code, and how the REPL surface starts it

## Short answer

There are two different Guiles installed, and they matter for different things:

- **Bare `guile` on your `$PATH` is Guile 2.2.7.** `which guile` resolves to
  `/usr/local/bin/guile`, which is a symlink to `guile-2.2`:

  ```
  $ which guile; guile --version
  /usr/local/bin/guile
  guile (GNU Guile) 2.2.7
  ```

- **This project's tooling does not use that one.** Its scripts explicitly
  prefer `guile3` (defined in `bin/guile-repl-paths.sh`), and `guile3` exists
  on this machine at `/usr/local/bin/guile3`, which is **Guile 3.0.10**:

  ```
  $ /usr/local/bin/guile3 --version   # (also reachable via ~/bin/guile, a symlink to it)
  guile (GNU Guile) 3.0.10
  ```

  So: **if you run `guile` yourself, you get 2.2.7. If you use this repo's
  REPL tooling (`gmake start`, `bin/guile-repl-server.sh`, etc.), the actual
  process that starts is Guile 3.0.10**, not the version bare `guile` would
  give you. README.org calls this out directly as the #1 thing that will bite
  you: "*Bare `guile` may be 2.2.7* ... Anything shelling out to `guile` fails
  in ways that look like your code is wrong. Everything here prefers `guile3`
  and prints which binary it chose."

  Confirmed which binary is actually chosen, via `bin/guile-repl-paths.sh`:

  ```
  $ ./bin/guile-repl-paths.sh
  slug        -home-jwalsh-ghq-github-com-dsp-dr-guile-skills
  log dir     <GUILE_REPL_ROOT>/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills
  repl port   42311
  proxy port  42312  (repl port + 1)
  guile       /usr/local/bin/guile3
  ```

## What the REPL surface actually gets started with

Running `./bin/guile-repl-server.sh` (equivalently `gmake start`) launches
**two** processes:

1. The REPL itself:
   ```
   guile3 --debug --listen=42311 -c '(sleep 86400)'
   ```
   (confirmed from the live process table: `guile3 --debug --listen=42311 -c
   (sleep 86400) (guile-3.0)`). `--debug` is not optional — without it Guile
   uses the fast VM engine and tracing/breakpoint meta-commands (e.g.
   `,trace`) silently do nothing, per `EXPERIMENTS.org` E3. If a `src/`
   directory exists at the project root it's added as `-L src`; on this
   checkout there is no `src/`, so no load path flag is added.

2. A logging proxy in front of it, written in Guile itself
   (`bin/guile-repl-proxy.scm`):
   ```
   guile3 ./bin/guile-repl-proxy.scm --listen 42312 --target 42311 \
       --log <GUILE_REPL_DIR>/repl.log
   ```
   It sits on `port+1`, forwards to the REPL on `port`, and tees the session
   to `repl.log` (rotated at 4 MiB, five generations, stored outside the repo
   under `$GUILE_REPL_ROOT/projects/<slug>/`, where `<slug>` is the absolute
   project path with every `/` and `.` turned into `-`).

Both bind `127.0.0.1` only — deliberately, since a Guile socket REPL is
unauthenticated arbitrary code execution.

`gmake start` output I actually captured on this box (ports reassigned to
42311/42312 for this isolated session):

```
repl   42311  (guile3 --debug, load path: src)
proxy  42312  -> 42311, logging to <GUILE_REPL_DIR>/repl.log
eval with: ./bin/guile-repl-eval.sh '(+ 1 1)'
```

and the resulting process table entries:

```
guile3 --debug --listen=42311 -c (sleep 86400) (guile-3.0)
guile3 ./bin/guile-repl-proxy.scm --listen 42312 --target 42311 --log .../repl.log (guile-3.0)
```

Evaluating through it (via `bin/guile-repl-eval.sh`, which talks to the proxy
port and strips the banner/prompt) confirms the runtime directly:

```
$ ./bin/guile-repl-eval.sh '(+ 1 1)'
$1 = 2

$ ./bin/guile-repl-eval.sh --raw '(version)'
GNU Guile 3.0.10
Copyright (C) 1995-2024 Free Software Foundation, Inc.
...
Enter `,help' for help.
$2 = "3.0.10"
```

`(version)` evaluated inside the actual running REPL returns `"3.0.10"` —
matching `guile3`, not the `guile` on your `$PATH`.

## Bottom line

- Code you run with a bare `guile` invocation: **Guile 2.2.7**.
- Code evaluated through this project's REPL surface (`gmake start` /
  `bin/guile-repl-server.sh` and friends): **Guile 3.0.10**, started as
  `guile3 --debug --listen=<port> -c '(sleep 86400)'` with a companion
  `guile3 bin/guile-repl-proxy.scm --listen <port+1> --target <port> --log
  <dir>/repl.log` logging proxy in front of it, both bound to 127.0.0.1 only.
