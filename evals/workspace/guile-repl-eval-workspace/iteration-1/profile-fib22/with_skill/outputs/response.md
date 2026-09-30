I connected to a running Guile REPL and defined the naive double-recursive `fib` exactly as you described:

```scheme
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
```

`(fib 22)` => `17711` (correct, F(22)=17711).

## The short answer

There is no single hot spot to optimize away — the time goes into raw call volume.
`(fib 22)` makes **57,313 calls to `fib`** (2·F(23)−1), and every one of those
calls does the same trivial amount of work: one comparison, one or two
subtractions, one addition, and — for all but the base cases — two more
recursive calls. The profiler confirms there's nothing else running: **100% of
self time is attributed to `fib` itself**, because the body never calls
anything but `fib` and the primitives `<`, `-`, `+` (which the VM executes
inline, with no separate stack frame to attribute time to). So "where does the
time go" has the same answer as "why is this slow": exponential call count on
a function whose real information content — the two preceding Fibonacci
numbers — is being recomputed from scratch, over and over, at every node of
the recursion tree.

## What I actually ran

First, `,time`, which is unambiguous and cheap:

```
scheme@(guile-user)> ,time (fib 22)
$1 = 17711
;; 0.003300s real time, 0.003298s run time.  0.000000s spent in GC.
```

(A separate fresh-REPL run of the same form earlier read 0.011318s — single-shot
timings on one call bounced between ~3ms and ~11ms, which I take to be
compile/warm-up noise rather than a real signal; see below for the more
trustworthy number.) No GC time at all — everything here is fixnum arithmetic,
so there's no allocation pressure to speak of.

Then I tried the sampling profiler directly on `(fib 22)`, and it did exactly
what the guile-repl-eval skill warns it will do on anything under ~0.5s:

```
scheme@(guile-user)> ,profile (fib 22)
No samples recorded.
```

A single `fib(22)` call finishes in a few milliseconds, too fast for a
statistical sampler with a ~10ms tick to catch anything. So I profiled a loop
of 1000 back-to-back `(fib 22)` calls instead — same call shape repeated, just
long enough to sample:

```
scheme@(guile-user)> ,time (let loop ((i 0)) (if (< i 1000) (begin (fib 22) (loop (+ i 1)))))
;; 0.640668s real time, 0.640645s run time.  0.000000s spent in GC.

scheme@(guile-user)> ,profile (let loop ((i 0)) (if (< i 1000) (begin (fib 22) (loop (+ i 1)))))
%     cumulative   self
time   seconds     seconds  procedure
100.00      9.20      0.61  <current input>:9:0:fib
  0.00      0.61      0.00  <current input>:9:9
---
Sample count: 61
Total time: 0.612545326 seconds (0.0 seconds in GC)
```

That gives a much more trustworthy per-call cost: **~0.64ms per `(fib 22)`
call**, i.e. roughly 11ns per recursive call across the 57,313 calls it makes.
100% of self time (0.61 of 0.61s sampled) sits in `fib`; the driving loop
itself is 0.00s self time, as expected. One profiler quirk worth flagging so
it doesn't get misread: the "cumulative" column shows 9.20s, over 15x the
0.61s total sampled — that's an artifact of `fib` appearing at every depth of
its own recursive call stack (~15 deep on average at `n=22`), so a flat
profiler credits the same wall-clock sample to `fib`'s cumulative time once
per stack frame it occupies. It's not a leak of time to some other place, and
self-time is not affected by it.

To make the "double recursion" shape concrete rather than just asserted, I
traced a small case, `(fib 4)`:

```
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

Note `(fib 2)` is computed twice and `(fib 1)` four times just to get to
`fib(4)` — that duplication compounds exponentially as `n` grows, which is
exactly the 57,313-calls-for-n=22 number above.

Finally, I checked the disassembly of `fib` to confirm there's no surprise
(e.g. boxing, generic dispatch) hiding in the compiled body:

```
(assert-nargs-ee/locals 2 6)
(<? 6 7)                      ; n < 2
...
(call-scm<-scm-uimm 1 6 1 3)  ; sub/immediate  (n - 1)
(handle-interrupts)
(call 5 2)                    ; recurse
(receive 2 5 8)
(call-scm<-scm-uimm 0 6 2 3)  ; sub/immediate  (n - 2)
(handle-interrupts)
(call 6 2)                    ; recurse
(receive 0 6 8)
(call-scm<-scm-scm 7 5 7 0)   ; add
(return-values)
```

Each call is a compact, direct bytecode sequence — a comparison, an
immediate-subtract, a `call`/`receive` pair (with a mandatory
`handle-interrupts` check before each), repeated twice, then an add. There's
no dynamic variable lookup or boxing overhead per call (the module-level
lookup of `fib` for self-reference is a one-time static-ref, not repeated).
So the per-call cost is essentially irreducible VM call/return + interrupt-check
overhead; the only lever that changes anything is *how many times* that body
runs — and that count is exponential in `n` because of the doubled, uncached
recursion.

**Bottom line:** the time isn't hiding in some expensive sub-operation — it's
spread almost perfectly evenly across ~57,000 near-identical, near-free calls
to `fib` itself (100% self time, no GC, no other procedures on the profile).
If you need this faster, the fix is algorithmic (memoize or go iterative), not
micro-optimization of the current body — there's nothing in the profile to
micro-optimize.
