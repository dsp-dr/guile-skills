#!/usr/bin/env guile3
!#
;; gen-icons.scm --- draw 5 candidate plugin icons as parametric curves in SVG.
;; Guile has no raster graphics, but SVG is just text, so this is the natural way
;; for a Guile skills repo to generate its own icon. Each curve is normalized to
;; fill a consistent fraction of the canvas so the five compare fairly.

;; `~,2f' is an (ice-9 format) directive, not one the core `simple-format'
;; understands. Without this import the script works only on a cold
;; auto-compile -- loading the compiler happens to pull (ice-9 format) in and
;; upgrade `format' process-wide -- and then fails on every later run, once the
;; .go is cached and no compiler is loaded. Measured on guile 3.0.10.
(use-modules (ice-9 format))

(define SIZE 256)
(define CENTER (/ SIZE 2))
(define TARGET-R (* 0.92 CENTER))  ; leave a small margin inside the rounded card
(define STEPS 480)

(define (points-for fn t-min t-max)
  (let loop ((i 0) (acc '()))
    (if (> i STEPS)
        (reverse acc)
        (let ((t (+ t-min (* (- t-max t-min) (/ i STEPS)))))
          (loop (+ i 1) (cons (fn t) acc))))))

(define (bounds pts)
  (let loop ((pts pts) (maxr 0.0))
    (if (null? pts)
        maxr
        (let* ((p (car pts)) (r (sqrt (+ (* (car p) (car p)) (* (cdr p) (cdr p))))))
          (loop (cdr pts) (max maxr r))))))

(define (scale-points pts)
  (let ((s (/ TARGET-R (bounds pts))))
    (map (lambda (p) (cons (* s (car p)) (* s (cdr p)))) pts)))

(define (points->attr pts)
  (string-join
   (map (lambda (p) (format #f "~,2f,~,2f" (+ CENTER (car p)) (+ CENTER (cdr p)))) pts)
   " "))

(define (svg-doc stroke polylines)
  (string-append
   (format #f "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ~a ~a\">\n" SIZE SIZE)
   (format #f "<rect width=\"~a\" height=\"~a\" fill=\"#1A1918\" rx=\"~a\"/>\n" SIZE SIZE (/ SIZE 8))
   (apply string-append
          (map (lambda (pts)
                 (format #f "<polyline fill=\"none\" stroke=\"~a\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\" points=\"~a\"/>\n"
                         stroke (points->attr pts)))
               polylines))
   "</svg>\n"))

;; Write beside this script, not into whatever directory the shell happens to
;; be in. Run from the repo root the old way, the candidates landed next to
;; .gitignore instead of under assets/, where the ignore rule expects them --
;; and an untracked file under a SHIPPED path fails check-version-bump before
;; the real test suite gets a chance to run.
(define OUT-DIR (dirname (car (command-line))))

(define (write-icon filename stroke polylines)
  (let ((path (string-append OUT-DIR "/" filename)))
    (call-with-output-file path
      (lambda (port) (display (svg-doc stroke polylines) port)))
    (format #t "wrote ~a\n" path)))

(define TAU (* 2 (acos -1)))

;; 1. Hypotrochoid (R=7 r=4 d=3 in unit steps) -- the wal.sh/research/curves signature curve.
(define (hypotrochoid t)
  (let* ((r-big 7) (r-small 4) (d 3)
         (diff (- r-big r-small))
         (ratio (/ diff r-small)))
    (cons (- (* diff (cos t)) (* d (cos (* ratio t))))
          (- (* diff (sin t)) (* d (sin (* ratio t)))))))

;; 2. Lissajous (a=3 b=2, phase pi/2)
(define (lissajous t)
  (cons (sin (+ (* 3 t) (/ (acos -1) 2))) (sin (* 2 t))))

;; 3. Rose curve r = cos(4 theta), 8 petals
(define (rose t)
  (let ((r (cos (* 4 t))))
    (cons (* r (cos t)) (* r (sin t)))))

;; 4. Lemniscate of Bernoulli, r^2 = cos(2t) -- only defined where cos(2t) >= 0,
;;    i.e. two separate lobes, t in [-pi/4,pi/4] and [3pi/4,5pi/4].
(define (lemniscate-lobe t)
  (let ((r (sqrt (max 0.0 (cos (* 2 t))))))
    (cons (* r (cos t)) (* r (sin t)))))

;; 5. Logarithmic (golden) spiral, a few turns
(define (log-spiral t)
  (let ((r (exp (* 0.18 t))))
    (cons (* r (cos t)) (* r (sin t)))))

(write-icon "icon-1-hypotrochoid.svg" "#D97757"
            (list (scale-points (points-for hypotrochoid 0 TAU))))
(write-icon "icon-2-lissajous.svg" "#7EC8E3"
            (list (scale-points (points-for lissajous 0 (* 2 TAU)))))
(write-icon "icon-3-rose.svg" "#F7B801"
            (list (scale-points (points-for rose 0 TAU))))
(write-icon "icon-4-lemniscate.svg" "#8BD450"
            (let ((lobe1 (points-for lemniscate-lobe (- (/ (acos -1) 4)) (/ (acos -1) 4)))
                  (lobe2 (points-for lemniscate-lobe (* 0.75 (acos -1)) (* 1.25 (acos -1)))))
              (let* ((all (append lobe1 lobe2))
                     (s (/ TARGET-R (bounds all))))
                (list (map (lambda (p) (cons (* s (car p)) (* s (cdr p)))) lobe1)
                      (map (lambda (p) (cons (* s (car p)) (* s (cdr p)))) lobe2)))))
(write-icon "icon-5-logspiral.svg" "#C77DFF"
            (list (scale-points (points-for log-spiral 0 (* 3 TAU)))))
