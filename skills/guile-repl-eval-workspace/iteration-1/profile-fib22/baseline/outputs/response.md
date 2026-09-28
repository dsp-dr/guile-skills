# Profiling `(fib 22)` (naive double recursion)

## Setup

Defined in a live `guile3 --debug --listen` REPL (via this repo's
`bin/guile-repl-eval.sh`):

```scheme
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
```

Sanity check: `(fib 10)` → `55`, `(fib 22)` → `17711`. Both correct.

## Headline answer

**Essentially all of the time is spent inside `fib` itself, executed a lot of
times — there is no other hot function to blame, and GC is negligible.** The
cost is the algorithm's exponential call count, not any particular
sub-operation.

## Evidence

**1. Call count matches the naive-recursion formula exactly.**

`(statprof (lambda () (fib 22)) #:count-calls? #t)` reports:

```
%     cumulative   self
time   seconds    seconds   calls   procedure
100.00      0.46      0.03   57313  <current input>:9:0:fib
  0.00      0.00      0.00       1  vm-trace-level
  ... (everything else 0.00%, all statprof/eval-loop bookkeeping)
---
Sample count: 3
Total time: 0.029390496 seconds (0.0 seconds in GC)
```

57,313 calls to `fib` for `(fib 22)`. That's exactly `2*F(23) - 1` (F(23) =
28657), the closed-form call count for naive double-recursive Fibonacci — i.e.
the branching factor is the golden ratio (~1.618) per unit decrease in `n`, so
work grows exponentially with `n` even though the *answer* only grows linearly
in digit count.

**2. Flat and tree profiles agree: 100% of self time is in `fib`, nothing
else.**

To get a statistically meaningful sample count I re-ran with more samples
(`#:loop 20 #:hz 1000`):

```
%     cumulative   self
time   seconds    seconds   calls   procedure
100.00      9.52      0.62 1146260  <current input>:9:0:fib
  0.00      0.00      0.00     ...  (statprof internals only)
---
Sample count: 721
Total time: 0.617721256 seconds (0.031839595 seconds in GC)
```

and with `#:display-style 'tree`:

```
100.0% fib at <current input>:9:0
```

1,146,260 calls = 20 × 57,313, confirming the loop ran cleanly. No frame for
`+`, `-`, or `<` ever shows up as its own line with nonzero self-time — Guile's
compiler open-codes these as inline VM primitives inside `fib`'s own bytecode,
so their cost is folded into `fib`'s self-time rather than appearing as
separate call overhead. There is no secondary hotspot to optimize around; the
entire cost is the recursive call/return machinery repeated 57k times.

**3. GC is a rounding error, not a contributor.**

The 20-loop run above shows only 0.032s of GC out of 0.618s total (~5%), and
that's driven mostly by statprof's own bookkeeping across many samples. For a
single un-instrumented `(fib 22)` I checked `gc-stats` directly:

```scheme
(begin (gc)
       (let ((b (assq-ref (gc-stats) 'gc-time-taken)))
         (fib 22)
         (list 'gc-delta (- (assq-ref (gc-stats) 'gc-time-taken) b))))
;; => (gc-delta 0)
```

Zero GC time for a single call — expected, since every intermediate value
(`n`, the two subtractions, the sum) is a fixnum up to 17711, so nothing here
allocates heap objects. The recursion cost is call-frame overhead and
arithmetic, not allocation.

**4. Real (un-instrumented) wall-clock cost, for scale.**

Timing `(fib 22)` directly with `get-internal-real-time` (no profiler
attached), 5 runs:

```
(6.15803e-4 6.13009e-4 6.12175e-4 6.12878e-4 6.30907e-4)   ; seconds
```

So a real, unsampled `(fib 22)` takes ~0.61–0.63 ms, i.e. roughly **11 ns per
call** across the 57,313 calls — consistent with compiled-VM function-call
overhead plus a comparison, two subtractions, and an addition per call, and
nothing more exotic.

(Side note, not part of the "where does the time go" answer but worth
flagging: the statprof runs above show ~30 ms/call-equivalent rather than
~0.6 ms — that gap is the sampling profiler's own per-sample stack-walk
overhead at `hz=1000` against a function this cheap, not a property of `fib`.
The *relative* attribution — 100% self-time in `fib`, ~0% GC, no other hot
procedure — is what's trustworthy from the profiler; the *absolute* per-call
timing should be read from the un-instrumented `get-internal-real-time`
measurement instead.)

## Bottom line

`(fib 22)` is slow (relative to its trivial output) purely because naive
double recursion calls `fib` 57,313 times to compute one answer — an
exponential (φⁿ) blow-up with no memoization and no early termination beyond
the `n < 2` base case. Every one of those calls does the same tiny constant
amount of work (one compare, two subtracts, one add, two recursive calls);
there's no library routine, no GC pause, and no single expensive line
absorbing the cost. If you want `(fib 22)` (or higher) to be fast, the fix is
algorithmic — memoize, or convert to the linear iterative/accumulator form —
not micro-optimizing anything inside the current body, since there's nothing
to micro-optimize: the entire profile is one line, `fib`, at 100%.
