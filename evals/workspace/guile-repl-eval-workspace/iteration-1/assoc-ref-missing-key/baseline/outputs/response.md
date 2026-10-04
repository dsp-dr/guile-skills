In Guile 3.0.10, `(assoc-ref '(("a" . 1)) "b")` returns `#f` for a key that isn't present in the alist. I verified this directly in a running REPL rather than guessing:

```
scheme@(guile-user)> (assoc-ref '(("a" . 1)) "b")
$1 = #f
```

(For comparison, a key that *is* present returns its associated value: `(assoc-ref '(("a" . 1) ("b" . 2)) "b")` gave `$5 = 2`.)

And yes, `assoc-ref` is available with no `use-modules`/`import` at all — it's part of the default top-level environment Guile starts you in. I confirmed this two ways in a fresh REPL session:

- I called `assoc-ref` immediately in the default `(guile-user)` module (`(module-name (current-module))` → `(guile-user)`) without requiring anything first, and it worked.
- I checked that the `assoc-ref` visible at the top level is literally the same binding as the one in the `(guile)` module:
  ```
  scheme@(guile-user)> (eq? assoc-ref (module-ref (resolve-module '(guile)) 'assoc-ref))
  $4 = #t
  ```
  `(guile)` is the module that's implicitly opened/used in every fresh Guile top-level environment (and in scripts run with plain `guile`), so anything bound there — `assoc-ref` included — is available "for free."

So to summarize:
- Missing key: returns `#f` (not an error, not `'()`).
- No import needed: `assoc-ref` comes from the `(guile)` module, which is part of the default environment.

Environment: Guile 3.0.10, verified via `(version)` → `"3.0.10"`.
