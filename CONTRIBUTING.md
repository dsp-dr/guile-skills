# Contributing

## Tooling, and the versions that matter

Verified on nexus, FreeBSD 15.1-RELEASE, 2026-09-28. "Minimum" means the repo's
own tooling breaks below it; where no minimum is given, anything current works.

| Tool | Minimum | Verified here | Needed for |
|---|---|---|---|
| `gh` | **2.90.0** | 2.101.0 | `gh skill publish` in the release gate |
| Guile 3 | 3.0 | 3.0.10 | everything; `guile3`, `guile-3.0` or `guile` |
| GNU make | — | 4.4.1 | `gmake` on FreeBSD, `make` on Linux |
| Python 3 | 3.9 | 3.11.15 | `tests/validate-evals.py` |
| `jq` | — | 1.8.1 | `admin/*.sh` |
| `pandoc` | — | 3.9.0.2 | `gmake readme` |
| `pass` | — | 1.7.4 | `admin/*.sh` only; not needed to contribute |
| Claude Code CLI | — | 2.1.261 | `claude plugin validate` |

The interpreter has three names in the wild — `guile3` on FreeBSD ports,
`guile-3.0` on Debian and Ubuntu, `guile` under Homebrew. Nothing here should
hard-code one; `bin/guile-repl-paths.sh`, the `Makefile` and
`tests/test-proxy.sh` all probe in that order. A hard-coded name is how the
logging proxy came to run on exactly one platform (see the v0.1.1 notes).

## Checking what you have

```sh
gh --version
gh skill --help >/dev/null 2>&1 && echo "gh skill: yes" || echo "gh skill: NO (need >= 2.90.0)"
for b in guile3 guile-3.0 guile; do command -v $b >/dev/null && printf '%-10s %s\n' $b "$($b --version | head -1)"; done
gmake --version | head -1; python3 --version; jq --version; pandoc --version | head -1
```

`gh skill` is a **preview** command: `gh skill --help` says so, and it may change
without notice. Its absence is the single most likely reason a release gate
behaves differently on your machine than on someone else's.

## Updating `gh`

`gh skill` landed in **v2.90.0** — it is absent in v2.89.0 and present from
v2.90.0 onward, with `publish` there from the start. `gh skill list` arrived
later, by v2.101.0.

- **FreeBSD.** The ports tree lags: `pkg` offered only 2.83.2_10 as of
  2026-09-28, which has no `gh skill` at all. Build it instead — there are no
  FreeBSD binaries in the upstream releases, only linux `.deb`/`.rpm`/`.tar.gz`:

  ```sh
  go install github.com/cli/cli/v2/cmd/gh@v2.101.0     # needs a Go toolchain
  ~/go/bin/gh --version                                 # reports 2.101.0
  ```

  Leave it at `~/go/bin/gh` rather than shadowing the packaged `gh`:
  `bin/release.sh` probes `gh` first and `$HOME/go/bin/gh` second, taking
  whichever actually answers `gh skill --help`. So the packaged `gh` stays your
  everyday client and the built one is used only where it is needed.

- **Debian / Ubuntu.** The official apt repository tracks latest; see
  `.github/workflows/gate.yml` for the exact keyring and source-list steps.
- **macOS.** `brew upgrade gh`.

Verify with `gh skill --help`, not with the version number alone — that is the
only check that matters, and it is what the tooling itself does.

## Before you push

```sh
gmake checks        # lint + check-evals + test; what CI runs
```

CI runs the same set on every push to `main` and every PR
(`.github/workflows/checks.yml`). A README-only change skips it, via
`paths-ignore`; for a mixed commit that should also skip, put `[skip ci]` in the
commit message.

`gmake test` starts real listeners on derived ports and cleans them up. If a run
is interrupted, check for survivors — a stale listener is indistinguishable from
a broken new one, which is the failure that cost the most time building this
repo:

```sh
./bin/guile-repl-server.sh --status
pgrep -fl guile-repl-proxy
```

## Conventions

- **Conventional commits**, and `--trailer` for co-authorship rather than a
  hand-typed trailer line.
- **Stage explicitly.** Never `git add -A` or `git add .`; look at what you are
  adding first. This repo has committed a 7.1 GB core dump once already.
- **A `git note` per commit** carrying context, considerations, deviations and
  timeline — the things a commit message should not carry but a reader six
  months out will want. Push them with
  `git push origin refs/notes/commits`; they do not travel with a normal push.
- **No secrets in the repo, ever.** `docs/secrets.md` is the runbook; values
  live in `pass` and reach the network on a pipe, never as a process argument.
- **Version bumps** are judged by `RELEASING.md`'s table, from the point of view
  of someone who pinned the previous tag.

## What this repo is opinionated about

Not style. There is no Guile linter, and this repo will never tell you to run
one — `guild compile -W 3` against a real output path is the whole of it
(`-o /dev/null` always fails: `guild` renames a temp file into place). What it
does police is whether you can tell what you actually ran. Prefer a measurement
over a claim, and when a check is silent, say that it was silent.
