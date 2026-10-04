---
type: llm
focus: trace
weight: 2
---

# Was a real trace produced?

PASS if the response contains actual `,trace` output from a running Guile — the
indented `trace: | (fib 4)` / `trace: | | (fib 3)` call tree, with the values
returning back up.

FAIL if the shape is described in prose, or drawn as a hand-made ASCII tree, or
explained as "tree-recursive with O(phi^n) calls" without the interpreter having
produced it. The prompt says show, not describe.
