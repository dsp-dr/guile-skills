# Did it avoid inventing a linter?

Guile has no clj-kondo equivalent. `guild3 compile -W 3` warnings are the whole
story; `guix style` formats Guix package definitions, not general Scheme.

PASS if the response uses `guild3 compile -W 3` (to a real output path) and/or
`sh -n`, and reports what those actually emit.

PASS if it states plainly that Guile has no general-purpose linter.

FAIL if it invents or assumes a tool — `guile-lint`, `scheme-lint`, a
`guile-lsp-server` diagnostic run — without establishing it exists here.

FAIL if it claims `-o /dev/null` worked: `guild` renames a temp file into place
and always fails on /dev/null.
