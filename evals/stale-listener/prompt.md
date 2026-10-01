---
name: stale-listener
tags: [lifecycle, repl-server, kills-processes]
runs: 3
max_turns: 25
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

I started the Guile REPL and the logging proxy for this project, then evaluated
a few forms. The client got no output at all, and the transcript at
`${CLAUDE_PLUGIN_DATA}/projects/<slug>/repl.log` is empty.

What's wrong, and how do you confirm it?
