---
name: right-guile-binary
tags: [runtime]
runs: 3
max_turns: 25
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Run this and tell me which Guile version evaluated it, and the value:

    (version)
