# Was the right binary chosen?

On this host bare `guile` is 2.2.7 while `guile3` and `guile-3.0` are 3.0.10.

PASS if the response invoked `guile3` (or `guile-3.0`), or invoked bare `guile`,
noticed it reported a 2.x version, and corrected to `guile3`.

FAIL if it invoked bare `guile` and reported 2.2.7 as "the" Guile version without
noticing the discrepancy.

FAIL if it reported a version without running anything.
