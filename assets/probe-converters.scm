#!/usr/bin/env guile3
!#
;;; probe-converters.scm --- which tool on this host can rasterise our SVG
;;;
;;; gen-icon.scm emits SVG, because Guile has no raster graphics.  Everything
;;; downstream that wants a PNG -- a marketplace listing, a README badge, a
;;; favicon, a GitHub social preview -- needs an external converter, and which
;;; converters exist differs between this FreeBSD host and a CI runner.
;;;
;;; Presence is not capability.  ImageMagick on FreeBSD reports SVG as rw+
;;; while using its own MSVG renderer, which silently drops strokes and gives
;;; you a plain rounded rectangle with no curve on it -- a PNG that converts
;;; fine and is wrong.  So each candidate is made to rasterise two SVGs: our
;;; icon, and the same icon with the curve removed.  A renderer that honours
;;; the curve produces a measurably larger PNG than one that drops it.  That is
;;; the difference between a check and a decoration.
;;;
;;; Usage:
;;;   guile3 assets/probe-converters.scm            # report, exit 0 if any works
;;;   guile3 assets/probe-converters.scm --json     # same, machine-readable
;;;   guile3 assets/probe-converters.scm convert [SIZE...]   # emit assets/icon-N.png
;;;
;;; Exit: 0 at least one converter renders faithfully
;;;       2 could not run, or nothing on this host renders faithfully
;;;         (2 is this repo's "inconclusive / cannot run" code -- see scripts/audit.sh)

(use-modules (ice-9 format)
             (ice-9 rdelim)
             (ice-9 ftw)
             (srfi srfi-1)
             (ice-9 binary-ports)
             (rnrs bytevectors))

;;; ---------------------------------------------------------------- paths

(define (script-dir)
  (dirname (car (command-line))))

(define ASSETS (script-dir))
(define REFERENCE-SVG (string-append ASSETS "/icon.svg"))

(define (tmp-root)
  ;; Honour the project's scratch convention before falling back to /tmp.
  (or (getenv "CLAUDE_CODE_TMPDIR")
      (getenv "TMPDIR")
      "/tmp"))

(define WORK (string-append (tmp-root) "/svg-probe-" (number->string (getpid))))

(define (ensure-dir d)
  (unless (file-exists? d) (mkdir d #o700)))

(define (rm-rf path)
  (when (file-exists? path)
    (if (eq? 'directory (stat:type (lstat path)))
        (begin
          (for-each (lambda (e)
                      (unless (member e '("." ".."))
                        (rm-rf (string-append path "/" e))))
                    (scandir path))
          (rmdir path))
        (delete-file path))))

;;; ---------------------------------------------------------------- shell

(define (shell-quote s)
  (string-append "'" (string-join (string-split s #\') "'\\''") "'"))

;; Guile 3.0.10 on FreeBSD 15.1 segfaults in BOTH `system*' and
;; `open-input-pipe': the crash is inside libc's
;; posix_spawn_file_actions_addclosefrom_np(), reached from scm_system_star,
;; and Guile 2.2.7 on the same host runs the identical form fine. So this
;; probe must not use either. `system' goes through system(3), not
;; posix_spawn, and is unaffected -- hence shelling out and reading the
;; output back from a file. If you are writing Guile tooling that shells
;; out on this host, you have the same constraint.
(define run-counter 0)

;; Set by run+capture, read by probe-one for the detail column. Single-threaded
;; probe, so a module-level cell is safe and keeps run+capture at two values.
(define last-status "ok")

(define (describe-status status)
  (let ((code (and (integer? status) (status:exit-val status)))
        (sig  (and (integer? status) (status:term-sig status))))
    (cond (sig (format #f "killed by signal ~a" sig))
          ((and code (not (zero? code))) (format #f "exit ~a" code))
          (else "ok"))))

(define (run+capture args)
  "Run ARGS (a list of strings), stderr folded into stdout.
Returns (values exit-status output-string). See the note above on why this
goes through `system' and a temporary file rather than a pipe."
  (set! run-counter (+ run-counter 1))
  (let* ((tmp (format #f "~a/run-~a.out" WORK run-counter))
         ;; `ulimit -c 0' because a candidate may abort rather than exit --
         ;; ImageMagick 7.1.2-25 does exactly that on this SVG -- and a core
         ;; dump in the tree is precisely what .gitignore:18 exists to catch.
         (cmd (string-append "ulimit -c 0; "
                             (string-join (map shell-quote args) " ")
                             " > " (shell-quote tmp) " 2>&1"))
         (status (system cmd))
         (out (if (file-exists? tmp)
                  (call-with-input-file tmp read-string)
                  "")))
    (when (file-exists? tmp) (delete-file tmp))
    ;; A tool killed by a signal has no exit value -- status:exit-val is #f
    ;; there, and treating that as success would hide a crashing converter.
    (set! last-status (describe-status status))
    (values (let ((code (and (integer? status) (status:exit-val status))))
              (if (and code (zero? code)) 0 1))
            (or out ""))))

(define (first-line s)
  (let ((i (string-index s #\newline)))
    (string-trim-both (if i (substring s 0 i) s))))

(define (which prog)
  "Resolve PROG on PATH without spawning anything."
  (if (string-index prog #\/)
      (and (file-exists? prog) prog)
      (let loop ((dirs (string-split (or (getenv "PATH") "") #\:)))
        (cond ((null? dirs) #f)
              ((string-null? (car dirs)) (loop (cdr dirs)))
              (else
               (let ((p (string-append (car dirs) "/" prog)))
                 (if (and (file-exists? p) (access? p X_OK)) p (loop (cdr dirs)))))))))

;;; ------------------------------------------------------------- PNG header
;;;
;;; IHDR is uncompressed, so dimensions are readable in pure Scheme: 8 bytes of
;;; signature, a 4-byte length, the tag "IHDR", then width and height as
;;; big-endian u32.  No zlib needed, and no asking the converter under test to
;;; vouch for its own output.

(define PNG-MAGIC #vu8(137 80 78 71 13 10 26 10))
(define IHDR-TAG #vu8(73 72 68 82))              ; "IHDR"

(define (bytes-match? bv offset expected)
  "True if BV contains EXPECTED (a bytevector) starting at OFFSET."
  (let ((n (bytevector-length expected)))
    (and (>= (bytevector-length bv) (+ offset n))
         (let loop ((i 0))
           (cond ((= i n) #t)
                 ((= (bytevector-u8-ref bv (+ offset i))
                     (bytevector-u8-ref expected i))
                  (loop (+ i 1)))
                 (else #f))))))

(define (png-dimensions file)
  "Return (WIDTH . HEIGHT) for FILE, or #f if it is not a PNG we can read."
  (and (file-exists? file)
       (> (stat:size (stat file)) 24)
       (let ((head (call-with-input-file file
                     (lambda (port) (get-bytevector-n port 24))
                     #:binary #t)))
         (and (bytevector? head)
              (= 24 (bytevector-length head))
              (bytes-match? head 0 PNG-MAGIC)
              (bytes-match? head 12 IHDR-TAG)
              (cons (bytevector-u32-ref head 16 (endianness big))
                    (bytevector-u32-ref head 20 (endianness big)))))))

;;; ------------------------------------------------- the differential fixture
;;;
;;; Two SVGs: the real icon, and the icon with every <polyline> stripped.  Any
;;; renderer that draws the curve must produce a bigger PNG from the first.

(define (read-file path)
  (call-with-input-file path read-string))

(define (strip-polylines svg)
  "Remove every <polyline .../> element from SVG source."
  (let loop ((s svg) (acc '()))
    (let ((start (string-contains s "<polyline")))
      (if (not start)
          (string-concatenate (reverse (cons s acc)))
          (let ((end (string-contains s "/>" start)))
            (if (not end)
                (string-concatenate (reverse (cons s acc)))
                (loop (substring s (+ end 2))
                      (cons (substring s 0 start) acc))))))))

(define (write-fixtures)
  (ensure-dir WORK)
  (unless (file-exists? REFERENCE-SVG)
    (format (current-error-port)
            "probe-converters: no ~a -- run gen-icon.scm first~%" REFERENCE-SVG)
    (exit 2))
  (let* ((svg (read-file REFERENCE-SVG))
         (bare (strip-polylines svg))
         (full-path (string-append WORK "/full.svg"))
         (bare-path (string-append WORK "/bare.svg")))
    (when (string=? svg bare)
      (format (current-error-port)
              "probe-converters: ~a has no <polyline> -- the fidelity test would be a decoration~%"
              REFERENCE-SVG)
      (exit 2))
    (call-with-output-file full-path (lambda (p) (display svg p)))
    (call-with-output-file bare-path (lambda (p) (display bare p)))
    (values full-path bare-path)))

;;; ----------------------------------------------------------- the candidates
;;;
;;; command      argv builder: (in out size) -> list of strings
;;; version      argv that prints a version, or #f
;;; freebsd/ci   package that provides it, for the install hint
;;; note         what to know before trusting it

(define CANDIDATES
  (list
   (list 'rsvg-convert
         (lambda (in out size)
           (list "rsvg-convert" "-w" (number->string size)
                 "-h" (number->string size) "-o" out in))
         '("rsvg-convert" "--version")
         "graphics/librsvg2-rust" "librsvg2-bin"
         "librsvg, the reference renderer -- prefer this")
   (list 'magick
         (lambda (in out size)
           (list "magick" "-background" "none" in
                 "-resize" (format #f "~ax~a" size size) out))
         '("magick" "-version")
         "graphics/ImageMagick7" "imagemagick"
         "check which SVG renderer it links: RSVG is faithful, XML/MSVG is not")
   (list 'convert
         (lambda (in out size)
           (list "convert" "-background" "none" in
                 "-resize" (format #f "~ax~a" size size) out))
         '("convert" "-version")
         "graphics/ImageMagick6" "imagemagick"
         "ImageMagick 6 CLI; same renderer caveat as magick")
   (list 'inkscape
         (lambda (in out size)
           (list "inkscape" "--export-type=png"
                 (string-append "--export-filename=" out)
                 "-w" (number->string size) "-h" (number->string size) in))
         '("inkscape" "--version")
         "graphics/inkscape" "inkscape"
         "heavy dependency; faithful but slow to install in CI")
   (list 'resvg
         (lambda (in out size)
           (list "resvg" "-w" (number->string size)
                 "-h" (number->string size) in out))
         '("resvg" "--version")
         "graphics/resvg" "(cargo install resvg)"
         "small and faithful; not packaged everywhere")
   (list 'cairosvg
         (lambda (in out size)
           (list "cairosvg" in "-o" out
                 "--output-width" (number->string size)
                 "--output-height" (number->string size)))
         '("cairosvg" "--version")
         "py311-cairosvg" "python3-cairosvg"
         "pulls in a Python stack")
   (list 'chromium
         (lambda (in out size)
           (list "chromium" "--headless" "--disable-gpu"
                 (string-append "--screenshot=" out)
                 (format #f "--window-size=~a,~a" size size)
                 (string-append "file://" in)))
         '("chromium" "--version")
         "www/chromium" "chromium-browser"
         "last resort: faithful, enormous, and screenshots a viewport not a canvas")))

(define (candidate-name c) (list-ref c 0))
(define (candidate-argv c) (list-ref c 1))
(define (candidate-version-argv c) (list-ref c 2))
(define (candidate-freebsd c) (list-ref c 3))
(define (candidate-ci c) (list-ref c 4))
(define (candidate-note c) (list-ref c 5))

;;; ---------------------------------------------------- ImageMagick renderer
;;;
;;; `-list format` names the delegate in parentheses: "(RSVG 2.x)" means it
;;; hands SVG to librsvg; "(XML 2.x)" means the internal MSVG renderer.

(define (imagemagick-svg-renderer prog)
  (and (which prog)
       (call-with-values (lambda () (run+capture (list prog "-list" "format")))
         (lambda (status out)
           (and (zero? status)
                (let loop ((lines (string-split out #\newline)))
                  (cond ((null? lines) #f)
                        ((let ((l (car lines)))
                           (and (string-contains l " SVG ")
                                (string-contains l "(")
                                (let* ((open (string-index l #\())
                                       (close (string-index l #\) open)))
                                  (and close (substring l (+ open 1) close)))))
                         => (lambda (r) r))
                        (else (loop (cdr lines))))))))))

;;; ------------------------------------------------------------- the probe

(define PROBE-SIZE 128)
(define FIDELITY-RATIO 1.25)   ; calibrated below; see the comment in the report

(define (file-size f) (if (file-exists? f) (stat:size (stat f)) 0))

(define (probe-one candidate full-svg bare-svg)
  "Returns an alist describing how CANDIDATE fared."
  (let* ((name (symbol->string (candidate-name candidate)))
         (path (which name)))
    (if (not path)
        `((tool . ,name) (verdict . absent) (path . #f))
        (let* ((version
                (call-with-values
                    (lambda () (run+capture (candidate-version-argv candidate)))
                  (lambda (s out) (if (zero? s) (first-line out) "?"))))
               (out-full (format #f "~a/~a-full.png" WORK name))
               (out-bare (format #f "~a/~a-bare.png" WORK name))
               (_ (for-each (lambda (f) (when (file-exists? f) (delete-file f)))
                            (list out-full out-bare)))
               (status-full
                (call-with-values
                    (lambda () (run+capture ((candidate-argv candidate)
                                             full-svg out-full PROBE-SIZE)))
                  (lambda (s out) s)))
               (dims (png-dimensions out-full)))
          (cond
           ((not (zero? status-full))
            `((tool . ,name) (verdict . failed) (path . ,path) (version . ,version)
              (detail . ,(format #f "~a -- cannot rasterise this SVG" last-status))))
           ((not dims)
            `((tool . ,name) (verdict . failed) (path . ,path) (version . ,version)
              (detail . "produced no readable PNG")))
           ((not (= PROBE-SIZE (car dims)))
            `((tool . ,name) (verdict . failed) (path . ,path) (version . ,version)
              (detail . ,(format #f "asked for ~ax~a, got ~ax~a"
                                 PROBE-SIZE PROBE-SIZE (car dims) (cdr dims)))))
           (else
            ;; Differential step: rasterise the curve-less SVG with the same tool.
            (call-with-values
                (lambda () (run+capture ((candidate-argv candidate)
                                         bare-svg out-bare PROBE-SIZE)))
              (lambda (s out)
                (let* ((size-full (file-size out-full))
                       (size-bare (file-size out-bare))
                       (ratio (if (> size-bare 0) (/ (* 1.0 size-full) size-bare) 0)))
                  (cond
                   ((or (not (zero? s)) (not (png-dimensions out-bare)))
                    `((tool . ,name) (verdict . works) (path . ,path)
                      (version . ,version) (dims . ,dims) (ratio . #f)
                      (detail . "renders, but the control SVG failed so fidelity is unproven")))
                   ((< ratio FIDELITY-RATIO)
                    `((tool . ,name) (verdict . lossy) (path . ,path)
                      (version . ,version) (dims . ,dims) (ratio . ,ratio)
                      (detail . ,(format #f "icon ~a B vs curve-less ~a B (x~,2f) -- the curve is being dropped"
                                         size-full size-bare ratio))))
                   (else
                    `((tool . ,name) (verdict . works) (path . ,path)
                      (version . ,version) (dims . ,dims) (ratio . ,ratio)
                      (detail . ,(format #f "icon ~a B vs curve-less ~a B (x~,2f)"
                                         size-full size-bare ratio))))))))))))))

(define (verdict-of r) (assq-ref r 'verdict))
(define (field r k) (assq-ref r k))

(define (probe-all)
  (call-with-values write-fixtures
    (lambda (full bare)
      (map (lambda (c) (probe-one c full bare)) CANDIDATES))))

;;; ------------------------------------------------------------- reporting

(define (host-line)
  (let ((u (uname)))
    (format #f "~a ~a ~a on ~a"
            (utsname:sysname u) (utsname:release u)
            (utsname:machine u) (utsname:nodename u))))

(define (freebsd?) (string=? "FreeBSD" (utsname:sysname (uname))))

(define (install-hint c)
  (if (freebsd?)
      (format #f "pkg install ~a" (candidate-freebsd c))
      (format #f "apt-get install -y ~a" (candidate-ci c))))

(define (report results)
  (format #t "~%SVG -> PNG converters~%")
  (format #t "host: ~a~%" (host-line))
  (format #t "fixture: ~a (~a B)~%" REFERENCE-SVG (file-size REFERENCE-SVG))
  (let ((im (or (imagemagick-svg-renderer "magick")
                (imagemagick-svg-renderer "convert"))))
    (when im
      (format #t "ImageMagick SVG renderer: ~a~a~%" im
              (if (string-contains (string-upcase im) "RSVG")
                  "  (librsvg -- faithful)"
                  "  (internal MSVG -- expect dropped strokes)"))))
  (newline)
  (format #t "~12a ~8a ~a~%" "TOOL" "VERDICT" "DETAIL")
  (format #t "~12a ~8a ~a~%" "────────────" "────────" "──────────────────────────────────────────")
  (for-each
   (lambda (r)
     (format #t "~12a ~8a ~a~%"
             (field r 'tool)
             (symbol->string (verdict-of r))
             (or (field r 'detail)
                 (case (verdict-of r)
                   ((absent) "not on PATH")
                   (else "")))))
   results)
  (newline)
  ;; Install hints only for what is missing and would help.
  (let ((missing (filter (lambda (c)
                           (eq? 'absent
                                (verdict-of (find (lambda (r)
                                                    (string=? (field r 'tool)
                                                              (symbol->string (candidate-name c))))
                                                  results))))
                         CANDIDATES)))
    (unless (null? missing)
      (format #t "not installed here:~%")
      (for-each (lambda (c)
                  (format #t "  ~14a ~40a ~a~%"
                          (candidate-name c) (install-hint c) (candidate-note c)))
                missing)
      (newline)))
  (let ((working (filter (lambda (r) (eq? 'works (verdict-of r))) results)))
    (if (null? working)
        (begin
          (format #t "VERDICT: no faithful converter on this host~%")
          (format #t "  gen-icon.scm output can be committed as SVG, but nothing here~%")
          (format #t "  can produce a trustworthy PNG. Install the first hint above.~%")
          2)
        (begin
          (format #t "VERDICT: ~a faithful converter~p: ~a~%"
                  (length working) (length working)
                  (string-join (map (lambda (r) (field r 'tool)) working) ", "))
          (format #t "  preferred: ~a~%" (field (car working) 'tool))
          0))))

(define (json-escape s)
  (string-concatenate
   (map (lambda (ch)
          (case ch
            ((#\") "\\\"") ((#\\) "\\\\") ((#\newline) "\\n")
            (else (string ch))))
        (string->list s))))

(define (report-json results)
  (format #t "{~%  \"host\": \"~a\",~%  \"fixture\": \"~a\",~%  \"tools\": [~%"
          (json-escape (host-line)) (json-escape REFERENCE-SVG))
  (let loop ((rs results) (first #t))
    (unless (null? rs)
      (let ((r (car rs)))
        (unless first (format #t ",~%"))
        (format #t "    {\"tool\": \"~a\", \"verdict\": \"~a\", \"path\": ~a, \"detail\": \"~a\"}"
                (field r 'tool) (verdict-of r)
                (if (field r 'path)
                    (format #f "\"~a\"" (json-escape (field r 'path)))
                    "null")
                (json-escape (or (field r 'detail) "")))
        (loop (cdr rs) #f))))
  (format #t "~%  ],~%")
  (let ((working (filter (lambda (r) (eq? 'works (verdict-of r))) results)))
    (format #t "  \"preferred\": ~a,~%"
            (if (null? working) "null" (format #f "\"~a\"" (field (car working) 'tool))))
    (format #t "  \"faithful_count\": ~a~%}~%" (length working))
    (if (null? working) 2 0)))

;;; ------------------------------------------------------------- conversion

(define DEFAULT-SIZES '(16 32 48 128 256 512))

(define (do-convert sizes results)
  (let ((working (filter (lambda (r) (eq? 'works (verdict-of r))) results)))
    (when (null? working)
      (format (current-error-port)
              "probe-converters: nothing here renders faithfully; refusing to write PNGs~%")
      (exit 2))
    (let* ((best (car working))
           (candidate (find (lambda (c) (string=? (symbol->string (candidate-name c))
                                                  (field best 'tool)))
                            CANDIDATES)))
      (format #t "using ~a (~a)~%" (field best 'tool) (field best 'version))
      (for-each
       (lambda (size)
         (let ((out (format #f "~a/icon-~a.png" ASSETS size)))
           (call-with-values
               (lambda () (run+capture ((candidate-argv candidate)
                                        REFERENCE-SVG out size)))
             (lambda (status output)
               (let ((dims (png-dimensions out)))
                 (if (and (zero? status) dims (= size (car dims)))
                     (format #t "  wrote ~a (~ax~a, ~a B)~%"
                             out (car dims) (cdr dims) (file-size out))
                     (begin
                       (format (current-error-port)
                               "  FAILED ~a: ~a~%" out (first-line output))
                       (exit 2))))))))
       sizes)
      0)))

;;; ------------------------------------------------------------------- main

(define (main args)
  (ensure-dir WORK)
  (dynamic-wind
    (lambda () #t)
    (lambda ()
      (let ((mode (if (null? (cdr args)) "probe" (cadr args))))
        (cond
         ((string=? mode "--json") (exit (report-json (probe-all))))
         ((or (string=? mode "probe") (string=? mode "--probe"))
          (exit (report (probe-all))))
         ((string=? mode "convert")
          (let ((sizes (if (null? (cddr args))
                           DEFAULT-SIZES
                           (map string->number (cddr args)))))
            (exit (do-convert sizes (probe-all)))))
         ((or (string=? mode "-h") (string=? mode "--help"))
          (format #t "usage: ~a [probe | --json | convert [SIZE...]]~%" (car args))
          (exit 0))
         (else
          (format (current-error-port) "probe-converters: unknown mode '~a'~%" mode)
          (exit 2)))))
    (lambda () (rm-rf WORK))))

(main (command-line))
