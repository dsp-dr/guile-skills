<!-- Generated from CONTRIBUTING.org by `gmake readme`. Edit the .org, not this file. -->

# Contributing

Upstream documentation this guide assumes and does not restate. Where this file and the documentation disagree, the documentation is right and this file is stale – say so in the PR.

| What | Where |
|----|----|
| Documentation index, for finding pages before searching | [code.claude.com/docs/llms.txt](https://code.claude.com/docs/llms.txt) |
| Plugin structure, components, loading and distribution | [Claude Code plugins](https://code.claude.com/docs/en/plugins) |
| `plugin.json`: every field, path rules, `userConfig`, the environment variables, the standard layout | [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference) |
| `SKILL.md` frontmatter, the `compatibility` field, directory rules | [Agent Skills specification](https://agentskills.io/specification) |

Three things from the manifest reference that this repository depends on, so that a reader knows where they came from:

- **The path variables resolve in Markdown bodies, not in the Bash environment.** `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` and `${CLAUDE_PROJECT_DIR}` are substituted into skill, command and agent content when it loads, and are "not present in the environment of commands Claude runs through the Bash tool". That is why `SKILL.md` hands the data directory to the scripts as `GUILE_SKILL_DATA="${CLAUDE_PLUGIN_DATA}"` rather than having them read it.
- **Never write state under `${CLAUDE_PLUGIN_ROOT}`**, which moves on every plugin update. `${CLAUDE_PLUGIN_DATA}` is `~/.claude/plugins/data/<id>/`, created on first reference and kept across updates – and deleted on uninstall unless `--keep-data`.
- **`bin/` is a reserved directory.** Files in it are on the Bash tool's `PATH` while the plugin is enabled, and "claude.ai and Cowork don't install a plugin that has this directory". This repository still has one; see issue \#2.

`claude plugin validate --strict` turns warnings into failures, which is what CI should use once the manifest is warning-free.

### Tooling, and the versions that matter

Verified on nexus, FreeBSD 15.1-RELEASE, 2026-09-28. "Minimum" means the repo's own tooling breaks below it; where no minimum is given, anything current works.

| Tool | Minimum | Verified here | Needed for |
|----|----|----|----|
| `gh` | **2.90.0** | 2.101.0 | `gh skill publish` in the release gate |
| Guile 3 | 3.0 | 3.0.10 | everything; `guile3`, `guile-3.0` or `guile` |
| GNU make | — | 4.4.1 | `gmake` on FreeBSD, `make` on Linux |
| Python 3 | 3.9 | 3.11.15 | `tests/validate-evals.py` |
| `jq` | — | 1.8.1 | `scripts/*.sh` |
| `pandoc` | — | 3.9.0.2 | `gmake readme` |
| `pass` | — | 1.7.4 | `scripts/*.sh` only; not needed to contribute |
| Claude Code CLI | — | 2.1.261 | `claude plugin validate` |

The interpreter has three names in the wild — `guile3` on FreeBSD ports, `guile-3.0` on Debian and Ubuntu, `guile` under Homebrew. Nothing here should hard-code one; `scripts/lib/guile-repl-paths.sh`, the `Makefile` and `tests/test-proxy.sh` all probe in that order. A hard-coded name is how the logging proxy came to run on exactly one platform (see the v0.1.1 notes).

### Checking what you have

```bash
gh --version
gh skill --help >/dev/null 2>&1 && echo "gh skill: yes" || echo "gh skill: NO (need >= 2.90.0)"
for b in guile3 guile-3.0 guile; do command -v $b >/dev/null && printf '%-10s %s\n' $b "$($b --version | head -1)"; done
gmake --version | head -1; python3 --version; jq --version; pandoc --version | head -1
```

`gh skill` is a **preview** command: `gh skill --help` says so, and it may change without notice. Its absence is the single most likely reason a release gate behaves differently on your machine than on someone else's.

### Updating `gh`

`gh skill` landed in **v2.90.0** — it is absent in v2.89.0 and present from v2.90.0 onward, with `publish` there from the start. `gh skill list` arrived later, by v2.101.0.

- **FreeBSD.** The ports tree lags: `pkg` offered only 2.83.2<sub>10</sub> as of 2026-09-28, which has no `gh skill` at all. Build it instead — there are no FreeBSD binaries in the upstream releases, only linux `.deb=/`.rpm=/=.tar.gz=:

  ``` bash
  go install github.com/cli/cli/v2/cmd/gh@v2.101.0     # needs a Go toolchain
  ~/go/bin/gh --version                                 # reports 2.101.0
  ```

  Leave it at `~/go/bin/gh` rather than shadowing the packaged `gh`: `scripts/release.sh` probes `gh` first and `$HOME/go/bin/gh` second, taking whichever actually answers `gh skill --help`. So the packaged `gh` stays your everyday client and the built one is used only where it is needed.

- **Debian / Ubuntu.** The official apt repository tracks latest; see `.github/workflows/gate.yml` for the exact keyring and source-list steps.

- **macOS.** `brew upgrade gh`.

Verify with `gh skill --help`, not with the version number alone — that is the only check that matters, and it is what the tooling itself does.

### Before you push

```bash
gmake checks        # lint + check-evals + test; what CI runs
```

CI runs the same set on every push to `main` and every PR (`.github/workflows/checks.yml`). A README-only change skips it, via `paths-ignore`; for a mixed commit that should also skip, put `[skip ci]` in the commit message.

`gmake test` starts real listeners on derived ports and cleans them up. If a run is interrupted, check for survivors — a stale listener is indistinguishable from a broken new one, which is the failure that cost the most time building this repo:

```bash
${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh --status
pgrep -fl guile-repl-proxy
```

### Testing a change

`gmake checks` proves the code is sound. It does not prove the **plugin** works, which is a separate question: the skills reference scripts by path, and a path that resolves in this repository may resolve nowhere else. Four layers, cheapest first.

#### 1. Deterministic checks

```bash
gmake checks        # lint + check-evals + test; exactly what CI runs
```

#### 2. Load the plugin from the working tree

```bash
gmake try           # claude --plugin-dir $(pwd)
```

Then ask it to do the thing — "start a Guile REPL for this project and trace `(fib 4)`" — and watch which commands it actually runs. `--plugin-dir` takes a directory or a `.zip` and is repeatable, so a second plugin can be loaded alongside.

#### 3. Load it with your working directory somewhere else

```bash
gmake try-in DIR=$HOME/ghq/github.com/dsp-dr/guile-sicp
```

**This is the test that matters**, and the one it is easiest to skip. Everything in this repo passes when the cwd is this repo. A `SKILL.md` that says `${CLAUDE_SKILL_DIR}/scripts/guile-repl-server.sh` works here and breaks in every other project, and only this layer catches it. Use a real project with real modules, not an empty directory.

#### 4. Check what an install actually delivers

```bash
gmake ship-check
```

Installs into a throwaway directory and lists every file a user receives, then says whether any of them is executable. `gh skill install` copies `skills/<name>/**` and nothing else, so a script outside that tree does not ship — and a skill whose documented commands are unusable as installed is the failure this target exists to make loud:

    executables shipped: NO -- any SKILL.md command naming a script is unusable as installed

#### Using the corpus

There are 30-plus Guile and Scheme checkouts under `~/ghq/github.com/` here. That is enough to answer "is this actually useful" with a matrix rather than an anecdote, and enough to shake out per-project assumptions — projects with no `src/`, projects whose modules need arguments, and derived-port collisions.

The worked example, against `guile-sicp` and its own modules:

```bash
cd ~/ghq/github.com/dsp-dr/guile-sicp
$GUILE_SKILLS/scripts/lib/guile-repl-paths.sh          # slug, ports, data root
$GUILE_SKILLS/skills/guile-repl-server/scripts/guile-repl-server.sh
$GUILE_SKILLS/skills/guile-repl-eval/scripts/guile-repl-eval.sh '(use-modules (sicp ch1)) (fib 10)'
# => $1 = 55
$GUILE_SKILLS/skills/guile-repl-eval/scripts/guile-repl-eval.sh '(use-modules (sicp ch1)) ,trace (fib 4)'
# => the indented call tree, exposing the exponential double recursion
$GUILE_SKILLS/skills/guile-repl-server/scripts/guile-repl-server.sh --stop
```

Report per project as **worked**, **worked with caveats**, or **failed**, and say why. Two things to check while you are there, because both are silent:

- The derived port pair. `37000 + cksum(slug) mod 900` gives each checkout its own pair, and worktrees — sibling or child — get their own too, since the slug is the absolute path. But `PORT+1` is not collision-checked against other projects, and across 33 checkouts here there are already two cases where one project's proxy port is another project's REPL port.
- Clean up. `--stop` before you leave, and `pgrep -fl guile-repl-proxy` afterwards. A stale listener is indistinguishable from a broken new one.

### Conventions

- **Conventional commits**, and `--trailer` for co-authorship rather than a hand-typed trailer line.
- **Stage explicitly.** Never `git add -A` or `git add .`; look at what you are adding first. This repo has committed a 7.1 GB core dump once already.
- **A `git note` per commit** carrying context, considerations, deviations and timeline — the things a commit message should not carry but a reader six months out will want. Push them with `git push origin refs/notes/commits`; they do not travel with a normal push.
- **No secrets in the repo, ever.** `docs/secrets.md` is the runbook; values live in `pass` and reach the network on a pipe, never as a process argument.
- **Version bumps** are judged by `RELEASING.md`'s table, from the point of view of someone who pinned the previous tag.

### What this repo is opinionated about

Not style. There is no Guile linter, and this repo will never tell you to run one — `guild compile -W 3` against a real output path is the whole of it (`-o /dev/null` always fails: `guild` renames a temp file into place). What it does police is whether you can tell what you actually ran. Prefer a measurement over a claim, and when a check is silent, say that it was silent.
