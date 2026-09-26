Here is a procedure:

    (define (fib n)
      (if (< n 2)
          n
          (+ (fib (- n 1)) (fib (- n 2)))))

What shape is the process `(fib 4)` generates? Show me, don't describe it.
