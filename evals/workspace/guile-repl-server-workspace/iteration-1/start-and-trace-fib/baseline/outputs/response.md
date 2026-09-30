# Started the REPL and traced (fib 4)

## Starting the REPL

```
$ ./bin/guile-repl-server.sh
repl   42331  (guile3 --debug, load path: src)
proxy  42332  -> 42331, logging to <GUILE_REPL_ROOT>/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
eval with: ./bin/guile-repl-eval.sh '(+ 1 1)'
```

Confirmed both are listening:

```
$ ./bin/guile-repl-server.sh --status
repl   42331  listening
proxy  42332  listening
log    <GUILE_REPL_ROOT>/projects/-home-jwalsh-ghq-github-com-dsp-dr-guile-skills/repl.log
```

Guile was started with `--debug`, which is required — without it the tracing
meta-commands (`,trace`) silently emit nothing and raise no error.

## Defining fib and evaluating it once

```
$ ./bin/guile-repl-eval.sh '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))'
(no output — definition accepted)

$ ./bin/guile-repl-eval.sh '(fib 4)'
$1 = 3
```

`(fib 4)` evaluates to 3, as expected.

## The call tree

Using the REPL's `,trace` meta-command:

```
$ ./bin/guile-repl-eval.sh ',trace (fib 4)'
trace: |  (fib 4)
trace: |  |  (fib 3)
trace: |  |  |  (fib 2)
trace: |  |  |  |  (fib 1)
trace: |  |  |  |  1
trace: |  |  |  |  (fib 0)
trace: |  |  |  |  0
trace: |  |  |  1
trace: |  |  |  (fib 1)
trace: |  |  |  1
trace: |  |  2
trace: |  |  (fib 2)
trace: |  |  |  (fib 1)
trace: |  |  |  1
trace: |  |  |  (fib 0)
trace: |  |  |  0
trace: |  |  1
trace: |  3
```

## Reading the tree

Each `|` level of indentation is one level of recursive call depth; a call
line is followed (once its subcalls finish) by the value it returned.

```
(fib 4)                      -> 3
├─ (fib 3)                   -> 2
│  ├─ (fib 2)                -> 1
│  │  ├─ (fib 1)             -> 1
│  │  └─ (fib 0)             -> 0
│  └─ (fib 1)                -> 1
└─ (fib 2)                   -> 1
   ├─ (fib 1)                -> 1
   └─ (fib 0)                -> 0
```

`fib(4)` makes 9 calls total (4, 3, 2, 2, 1, 1, 1, 0, 0), matching the
classic exponential-blowup shape of naive recursive Fibonacci: `fib(2)` is
recomputed twice, and `fib(1)`/`fib(0)` are recomputed from scratch at every
branch that bottoms out.

## Cleanup

Stopped the REPL and its logging proxy:

```
$ pkill -f "listen=42331"
$ pkill -f "guile-repl-proxy.scm --listen 42332"
```
