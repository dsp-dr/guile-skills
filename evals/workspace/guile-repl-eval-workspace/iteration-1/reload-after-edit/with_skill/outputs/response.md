Yes, your change took effect — but only after I explicitly reloaded the module. Here's what happened:

**1. First I called the currently-loaded `greet` to see what the REPL had in memory:**

```
./bin/guile-repl-eval.sh '(use-modules (mymod)) (greet "world")'
$4 = "hello, world"
```

That's the *old* body — the REPL had `mymod.scm` loaded from before your edit, and a module that's already loaded does not automatically pick up file changes (a plain `use-modules` on an already-loaded module is a no-op).

**2. So I reloaded the module explicitly:**

```
./bin/guile-repl-eval.sh "(reload-module (resolve-module (quote (mymod))))"
```

which produced:

```
;;; note: source file .../src/mymod.scm
;;;       newer than compiled .../mymod.scm.go
;;; compiling .../src/mymod.scm
;;; compiled .../mymod.scm.go
$5 = #<directory (mymod) 82beca280>
```

confirming Guile noticed the source file was newer than its compiled cache and recompiled it.

**3. Then I called `greet` again:**

```
./bin/guile-repl-eval.sh '(use-modules (mymod)) (greet "world")'
$6 = "howdy, world!"
```

**Bottom line:** your edit to `greet` (now returning `"howdy, " name "!"` instead of the old `"hello, " name`) is confirmed live in the running REPL. It didn't take effect automatically on its own — I had to run `(reload-module (resolve-module '(mymod)))` to force Guile to recompile and re-bind the module from the edited source before the new behavior showed up.
