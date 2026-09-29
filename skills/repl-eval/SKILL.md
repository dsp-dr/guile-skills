---
name: repl-eval
description: Evaluate Scheme in a running Guile REPL over its socket, and use tracing, breakpoints, macro expansion and profiling from it. Use whenever a claim about Guile code should be checked by running it - before asserting an API exists, after editing a module, or when asked what shape a recursion has.
license: MIT
allowed-tools: Read
compatibility: Requires nc and a POSIX shell, plus a Guile 3 socket REPL already listening on loopback. Starts no processes of its own. Designed for Claude Code or a similar product.
metadata:
  requires:
    binaries:
      - nc
    binaries-fallback:
      - guile3
    optional-binaries: none
    process: none; talks to an already-running REPL
    ports: connects to 127.0.0.1:PORT+1 (proxy) or PORT (direct)
    filesystem:
      - <project>/  (r; whatever the evaluated code reads)
    network:
      - 127.0.0.1 only
    credentials: none
    danger: >-
      a Guile socket REPL is unauthenticated arbitrary code execution;
      bind 127.0.0.1 only, never 0.0.0.0 and never through a tunnel
  verified-on: FreeBSD 15.1-RELEASE, guile3 3.0.10, 2026-09-26
  enforcement: >-
      the requires block is documentation, not a sandbox: nothing in the harness
      reads it. This skill's Bash calls are diagnostic commands (nc, pkill, ps,
      lsof, sockstat, guild3, curl) too varied to pre-approve narrowly without
      either breaking legitimate use or granting a de-facto blanket Bash grant,
      so allowed-tools deliberately omits Bash: the user approves each call.
      Real gating is settings.json permissions and
      `claude plugin eval --allow-tools` at eval time
---

# Evaluate before you assert

The failure this prevents is claiming success without running anything — the
second most-policed anti-pattern across 75 close-read Clojure skills, and
identical in Guile. The socket REPL is what makes "verified" checkable.

```sh
sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-eval.sh '(+ 1 1)'                   # => $1 = 2
sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-eval.sh '(use-modules (my mod)) (my-proc 3)'
echo '(assoc-ref my-alist "k")' | sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-eval.sh
sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-eval.sh --raw ',trace (fib 4)'      # keep banner and prompt
sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-eval.sh --direct '(+ 1 1)'          # bypass the proxy, no log
```

Output is stripped of the eight-line banner and the trailing prompt, so what you
read back is the value.

## What the REPL gives you beyond eval

| Ask | Meta-command | Answers |
|---|---|---|
| what shape is this process? | `,trace FORM` | indented call tree with arguments and returns |
| how does it grow? | `,time FORM` | real, run and GC time separately |
| where does the time go? | `,profile FORM` | flat profile, self and cumulative |
| what did the macro expander do? | `,expand FORM` | expanded source |
| what did the optimiser do? | `,optimize FORM` | partially evaluated source |
| what bytecode? | `,disassemble PROC` | VM instructions |
| stop here | `,break PROC` then `,bt` | breakpoint, backtrace |

## Traps that will mislead you

- **`,profile` on a fast form prints `No samples recorded.`** It is a sampling
  profiler with nothing to sample, not a broken profiler. Use a workload of at
  least ~0.5 s.
- **`,locals` may report "No local variables"** at a frame where an argument is
  clearly in scope. Unexplained. Do not conclude the variable is unbound.
- **Each connection is a fresh REPL.** `$N` numbering restarts and bindings from
  a previous invocation are gone. State only persists within one connection.
- **Reload after editing.** A module already loaded does not pick up file
  changes: `(reload-module (resolve-module '(my mod)))`. Redefining a record type
  or a GOOPS class leaves existing instances on the old definition.
- **There is no linter.** `guild3 compile -W 3 -o /tmp/x.go file.scm` gives
  warnings, and that is the whole story — no clj-kondo equivalent exists. Never
  instruct anyone to "run the linter". (`-o /dev/null` always fails: `guild`
  renames a temp file into place.)

## Documentation

Full write-up, including the three binary names this probes across FreeBSD,
Debian/Ubuntu and Homebrew: <https://wal.sh/tools/plugins/guile-skills/>
Source and issues: <https://github.com/dsp-dr/guile-skills>
