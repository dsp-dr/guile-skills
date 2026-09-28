# Releasing

This plugin's version lives in one place: `version` in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json). Raise it on every
release — the directory and `gh skill install --pin` both key off it.

## What counts as patch / minor / major

Semver, judged against what an installer of this plugin actually depends on:
the three skills' behavior and their `SKILL.md` contracts, `bin/*.sh` as a
public interface, and the plugin manifest itself.

| Bump | When |
|---|---|
| **patch** | Wording/doc fixes in a `SKILL.md` or this repo's own docs; a `bin/*.sh` fix that doesn't change its arguments or output shape; adding a regression test; anything in `evals/` or the `*-workspace/` benchmark output. |
| **minor** | A new skill added; a new optional flag on a `bin/*.sh` script; a `SKILL.md` description or instructions change that widens *when* it triggers or *what it covers*, without breaking an existing caller. |
| **major** | Removing or renaming a skill or a `bin/*.sh` script; changing a script's existing argument/output contract; changing the derived-port scheme in `guile-repl-paths.sh`; anything that would silently break someone who scripted against the previous version. |

When in doubt, look at it from `gh skill install dsp-dr/guile-skills <skill> --pin vX.Y.Z` — a bump is major exactly when pinning the *old* tag stops being a reasonable way to avoid the change.

## Cutting one

```sh
gmake release-staging                    # regression tests + validate + dry-run, no publish
gmake release-production TAG=v0.2.0      # same gate, then the real `gh skill publish --tag`
```

`release-production` refuses to publish if the gate fails. It also drives the
same `release:start` / `release:end` labels the CI gate uses
(`.github/workflows/gate.yml`) when run against a PR — apply `release:skip`
to a PR to bypass the gate (e.g. a docs-only change), the same escape hatch
`labeler:skip` gives the path labeler.

`gh skill publish` handles the GitHub side: it tags the release, adds the
`agent-skills` topic if the token has admin on the repo, and prints the
`gh skill install` / `--pin` commands for that version.
