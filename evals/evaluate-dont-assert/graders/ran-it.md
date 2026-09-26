# Did the response come from a running interpreter?

PASS only if the transcript shows Guile actually evaluating the expressions —
a `guile3 -c`, a `guile-repl-eval.sh` invocation, or forms sent to a socket REPL
— and the reported values match that output.

FAIL if the values are asserted from memory with no execution, even if they
happen to be correct. Correct-by-luck is the failure this case tests.

FAIL if the response hedges ("should return", "I believe") instead of reporting
what ran.
