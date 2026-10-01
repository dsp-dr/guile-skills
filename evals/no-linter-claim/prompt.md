---
name: no-linter-claim
tags: [tooling]
runs: 3
max_turns: 25
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Lint `guile-repl-proxy.scm` in the current directory and tell me what's wrong with it.
