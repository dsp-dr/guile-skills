## `(assoc-ref '(("a" . 1)) "b")` for a missing key

I checked this by starting the project's Guile 3 socket REPL
(`./bin/guile-repl-server.sh`, guile3 3.0.10) and evaluating directly rather
than guessing:

```
./bin/guile-repl-eval.sh '(assoc-ref (list (cons "a" 1)) "b")'
$1 = #f
```

**It returns `#f`.** `assoc-ref` never signals an error for a missing key —
it just gives you `#f`, which is indistinguishable from a key that is present
with the value `#f`. If you need to tell "absent" apart from "present but
`#f`", use `assoc` directly (it returns `#f` on miss but the whole pair
`("b" . #f)` on a hit) rather than `assoc-ref`.

## Is `assoc-ref` available without importing anything?

Yes. I verified this in the running REPL, in the default module a script or
REPL starts in, with no `(use-modules ...)` of my own:

```
./bin/guile-repl-eval.sh "(module-name (current-module))"
$2 = (guile-user)

./bin/guile-repl-eval.sh "(variable-bound? (module-variable (current-module) 'assoc-ref))"
$3 = #t

./bin/guile-repl-eval.sh "(map module-name (module-uses (current-module)))"
$7 = ((guile) (system base compile) (value-history))
```

and confirmed the binding `assoc-ref` resolves to in `guile-user` is the
exact same variable object as the one in the `(guile)` module:

```
./bin/guile-repl-eval.sh "(eq? (module-variable (resolve-module '(guile)) 'assoc-ref) (module-variable (current-module) 'assoc-ref))"
$8 = #t
```

So `assoc-ref` isn't coming from SRFI-1 or some other library you'd need to
`use-modules` — it's exported by the `(guile)` module itself, which is the
module every Guile REPL/script auto-uses by default. That means you can call
`assoc-ref` with zero `use-modules` calls, in a completely fresh Guile 3
process.
