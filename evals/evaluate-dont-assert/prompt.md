---
name: evaluate-dont-assert
tags: [evaluate, repl-eval]
runs: 3
max_turns: 25
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Does Guile 3 have a `string-join` procedure? If so, what exactly does
`(string-join '("a" "b" "c") "-")` return, and what does it return when the
delimiter argument is omitted?

Answer with the actual values.
