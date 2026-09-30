---
name: emacs-setup
description: Set a Guile project up for Emacs and Geiser - detect where its modules actually live, propose a .dir-locals.el that probes for the Guile 3 binary and derives this checkout's REPL ports at load time, and verify Emacs and the shell agree before anyone connects. Use when asked to set up Emacs, Geiser, geiser-connect or interactive debugging for a Guile or Scheme project, or when (use-modules ...) fails in Geiser because the load path is wrong.
license: MIT
allowed-tools: Read
compatibility: Requires Guile 3 (guile3, guile-3.0 or guile), GNU Emacs 29 or later (the oldest version in this project's CI; older is unverified) with Geiser and geiser-guile for the interactive half, and a POSIX shell. Writes one file, .dir-locals.el, at the project root. Designed for Claude Code or a similar product.
metadata:
  requires:
    binaries:
      - emacs
      - guile3
    binaries-fallback:
      - guile
    emacs-packages:
      - geiser
      - geiser-guile
    filesystem:
      - <project>/.dir-locals.el  (rw; proposed on stdout, written only after review)
      - ${CLAUDE_PLUGIN_DATA}/projects/<slug>/  (r; the transcript that proves Geiser went through the proxy)
    network:
      - 127.0.0.1 only
    credentials: none
  verified-on: macOS (Darwin 24.1, arm64), GNU Emacs 32.0.50 (a development build), Homebrew guile 3.0.10, 2026-09-30. Not yet run on FreeBSD, or under CI's Emacs 29.3
  enforcement: >-
      allowed-tools omits Bash for the same reason as repl-server: the calls
      here (emacs --batch, the detector, the generator) are approved one by one.
      Nothing is written by a script; the skill writes .dir-locals.el itself
      after showing it.
---

# Emacs and Geiser for a Guile project

The deliverable is a project where a person opens a `.scm` file, runs one
command, and lands in **this project's** REPL, with this project's load path,
recorded through the logging proxy. It is not done until the result has been checked.

Two mistakes this skill exists to prevent, both found in real checkouts:

- **Assuming `src/`.** Across 48 local Scheme checkouts `src/` held the modules
  in 21, which is 43%. `irc/`, `lib/`, `modules/` and the repository root all occur.
- **Pinning the binary.** `geiser-guile-binary "guile3"` works on FreeBSD and
  fails on Debian (`guile-3.0`) and Homebrew (`guile`). It is the Emacs form of
  hard-coding the interpreter name in a shell script.

## 1. Measure the project

Run from the project root. The ports are derived from the working directory **as
spelled**, so the directory matters. On a symlinked path (macOS `/tmp`, `/var`, or a
symlinked `~/ghq`), start the REPL from the same spelling Emacs will visit the
files under. The physical and logical spellings give different ports:

```sh
sh ${CLAUDE_SKILL_DIR}/scripts/guile-project-detect.sh
GUILE_SKILL_DATA="${CLAUDE_PLUGIN_DATA}" sh ${CLAUDE_SKILL_DIR}/scripts/guile-repl-paths.sh
```

Report the module directories, the load path, the binary and the two ports. If
the detector finds **no modules**, say that the project is scripts rather than a
library, and do not invent a load path.

Check the binary is 3.x (`<binary> --version`). A present `guile` can be 2.2.7.
Stop on 2.x.

## 2. Check Emacs can do this at all

```sh
emacs --batch --eval '(dolist (p (list "geiser" "geiser-guile")) (princ (format "%s %s\n" p (if (locate-library p) "found" "MISSING"))))'
```

If either is missing, say so and give the install (`M-x package-install RET
geiser-guile`, or the distribution package). Don't write a configuration that
cannot load, and don't call the job done if you did.

## 3. Propose `.dir-locals.el`, then write it

```sh
sh ${CLAUDE_SKILL_DIR}/scripts/guile-dir-locals.sh
```

This prints a proposal and writes nothing. Everything in it is evaluated when
Emacs loads it: the binary probe (`guile3`, `guile-3.0`, `guile`), the load path
(relative to the file), and the ports (the same `37000 + cksum(slug) mod 900` as
the shell). So it is safe to commit, and it stays correct in every checkout and
worktree.

- **No existing file:** show the proposal, then write it with the Write tool.
- **An existing file:** merge rather than overwrite. Keep every entry you did not
  generate, and say exactly what you added or replaced. A pinned
  `geiser-guile-binary` in the old file is the one thing worth replacing, and
  you should say why.

Tell the person about the prompt before they see it. Because the file contains
`eval` forms, Emacs asks on first visit whether the values are safe; answering
`!` marks that exact form safe for good. In a headless or tmux-driven Emacs the
prompt looks like a hang. Do **not** suggest `enable-local-variables :all` to
silence it: that applies every unsafe local variable in every directory, without
asking (Emacs 30.2 `files.el:4118-4147`, measured: an `eval` ran under `:all` with
`enable-local-eval` at its default `maybe`).

## 4. Verify before anyone connects

```sh
sh ${CLAUDE_SKILL_DIR}/scripts/guile-dir-locals.sh --verify
```

This loads the file in `emacs -Q --batch` and compares the repl port, proxy port
and load path Emacs computes with what the shell computes. It exits nonzero on
any disagreement. **Do not report success on a FAIL line.** A silent
disagreement about the port means Geiser connects to some other project's REPL,
or to nothing.

## 5. Start the REPL on the same load path, then connect

Use the `repl-server` skill, started from the same directory. That script
defaults to `SRC_DIR=src`, so pass the detected directory explicitly when it
isn't `src`:

```sh
SRC_DIR=<first module dir> GUILE_SKILL_DATA="${CLAUDE_PLUGIN_DATA}" sh <repl-server>/scripts/guile-repl-server.sh
```

Then in Emacs: open any `.scm` file in the project, accept the local-variables
prompt, and run `M-x guile-project-connect`. That connects Geiser to the
**proxy** port, so the human's session is recorded as well as the agent's.

Geiser documents this path, attaching to an external `guile --listen`, in
[Starting the REPL](https://www.nongnu.org/geiser/The-REPL.html#Starting-the-REPL).
`M-x geiser` or `M-x run-guile` would start a separate Guile that is not this
project's REPL and records nothing (`run-geiser` is an obsolete alias since
Geiser 0.26).

## 6. What "working" means

Batch mode loads Geiser but never runs a REPL, so step 4 proves the
configuration and not the connection. The connection is proved by:

1. A `scheme@(guile-user)>` prompt in the Geiser REPL buffer. Run
   `guile-project-connect` from a `.scm` buffer: Geiser reads that buffer's
   `geiser-guile-load-path` at connect time and sends it to the REPL
   (geiser-guile 0.28.3, `geiser-guile.el:667-681`), which also means connecting
   changes the shared REPL's `%load-path`, debug options and terminal width.
2. `(use-modules (<a module the detector found>))` succeeding there.
3. `,bt` after a forced error returning frames, and `,trace` on a small call
   returning more than zero lines (both need the REPL's `--debug`, which
   `repl-server` always passes).
4. The transcript under `${CLAUDE_PLUGIN_DATA}/projects/<slug>/repl.log`
   growing, which shows the session went through the proxy.

If this plugin's `geiser-setup` agent is available, it drives a real Emacs in
tmux and checks all four. That agent ships with the plugin and is **not**
installed by `gh skill install`. Without it, give the person these four checks
to run, and report the configuration as verified and the connection as
**not yet exercised**. Those are different claims.

## What to hand back

The binary and version, the module directories and load path, both ports, the
`.dir-locals.el` you wrote (or what you merged), the `--verify` output, the
Geiser status, and anything not done, stated as not done.

## Documentation

<https://wal.sh/tools/plugins/guile-skills/> · source:
<https://github.com/dsp-dr/guile-skills>
