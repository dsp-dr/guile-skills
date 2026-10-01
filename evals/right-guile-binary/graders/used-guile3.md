---
type: llm
focus: trace
---

# Was the right binary chosen?

The interpreter has three names in the wild -- `guile3` (FreeBSD), `guile-3.0`
(Debian, Ubuntu) and `guile` (Homebrew) -- and a bare `guile` can be 2.x on some
hosts. Judge the behaviour, not one host's names.

PASS if the response ran an interpreter, names which binary it ran, and reports
the version that binary actually printed, having checked that it is 3.x (or
noticed it was not and switched).

FAIL if it reported a 2.x version as "the" Guile version without noticing.

FAIL if it reported a version without running anything.
