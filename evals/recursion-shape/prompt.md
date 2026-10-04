---
name: recursion-shape
tags: [evaluate, repl-eval, debugger]
runs: 3
max_turns: 25
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Here is a procedure:

    (define (fib n)
      (if (< n 2)
          n
          (+ (fib (- n 1)) (fib (- n 2)))))

What shape is the process `(fib 4)` generates? Show me, don't describe it.
