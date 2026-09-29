#!/bin/sh
# -*- scheme -*-
# Shell trampoline. Guile reads this whole block as a comment, so the file is
# both a POSIX shell script and a Guile program. It exists because the
# interpreter has three names in the wild: guile3 on FreeBSD ports, guile-3.0 on
# Debian and Ubuntu, guile under Homebrew. A hard-coded `env guile3' shebang
# worked on nexus and failed silently everywhere else -- the proxy never
# started, which surfaced as an empty transcript rather than as an error, and
# CI on ubuntu-latest is what caught it. EXPERIMENTS.org E9 is the same class.
#
# Do not name the closing delimiter in this comment: writing those two
# characters here ends the block early and Guile then fails on the next line.
exec "$(command -v guile3 || command -v guile-3.0 || command -v guile)" -s "$0" "$@"
!#
;;; guile-repl-proxy.scm --- a logging TCP proxy in front of a Guile socket REPL
;;;
;;; `guile3 --debug --listen=PORT' gives you a REPL an agent can drive, but
;;; nothing records what went through it. This sits on PORT+1, forwards bytes
;;; both ways unchanged, and writes a timestamped transcript to a per-project
;;; log directory. Connect your agent to the proxy port and the session is
;;; traced; connect to the REPL port directly and it is not.
;;;
;;; Usage:
;;;   guile-repl-proxy.scm --listen 37497 --target 37496 --log /path/to/x.log
;;;
;;; The transcript marks direction: "->" is client to REPL (what was asked),
;;; "<-" is REPL to client (what came back). Bytes are forwarded verbatim; the
;;; log is a readable rendering of them, not the transport.

(use-modules (ice-9 getopt-long)
             (ice-9 binary-ports)
             ;; (ice-9 format), not the core simple-format: the millisecond
             ;; padding below uses ~3,'0d, which the core format cannot do.
             (ice-9 format)
             (rnrs bytevectors)
             (srfi srfi-1))

(define (iso-8601-now)
  (strftime "%Y-%m-%dT%H:%M:%SZ" (gmtime (current-time))))

(define (clock-now)
  "Wall clock with milliseconds, for interleaving lines within a session."
  (let* ((now (gettimeofday))
         (secs (car now))
         (usecs (cdr now)))
    (format #f "~a.~3,'0d"
            (strftime "%H:%M:%S" (localtime secs))
            (quotient usecs 1000))))

(define (mkdir-p path)
  "Create PATH and any missing parents. Silent when it already exists."
  (let loop ((parts (filter (lambda (s) (not (string-null? s)))
                            (string-split path #\/)))
             (so-far ""))
    (unless (null? parts)
      (let ((next (string-append so-far "/" (car parts))))
        (unless (file-exists? next)
          (catch 'system-error
            (lambda () (mkdir next))
            ;; A parallel session may have won the race; only an existing
            ;; directory is an acceptable reason for mkdir to fail here.
            (lambda args
              (unless (file-exists? next) (apply throw args)))))
        (loop (cdr parts) next)))))

(define max-log-bytes
  ;; 4 MiB: a long tracing session is tens of kilobytes, so this holds many
  ;; sessions, and five generations bound the directory at ~20 MiB per project.
  (* 4 1024 1024))

(define max-log-generations 5)

(define (rotate-logs! log-file)
  "Rotate LOG-FILE if it has grown past MAX-LOG-BYTES.

Keeps LOG-FILE.1 .. LOG-FILE.N, oldest discarded. Called once at startup and
again between connections, so a session is never cut in half mid-transcript."
  (when (and (file-exists? log-file)
             (> (stat:size (stat log-file)) max-log-bytes))
    ;; Walk down from the oldest so nothing is overwritten before it moves.
    (let loop ((n (- max-log-generations 1)))
      (when (>= n 1)
        (let ((older (format #f "~a.~a" log-file n))
              (newer (format #f "~a.~a" log-file (+ n 1))))
          (when (file-exists? older)
            (if (= (+ n 1) max-log-generations)
                (delete-file older)          ; falls off the end
                (rename-file older newer))))
        (loop (- n 1))))
    (rename-file log-file (string-append log-file ".1"))))

(define (log-chunk log-port direction bv)
  "Render BV into LOG-PORT, one line per line of payload, tagged with DIRECTION."
  (let* ((text (false-if-exception (utf8->string bv)))
         (text (or text (format #f "#<~a non-utf8 bytes>" (bytevector-length bv))))
         (lines (string-split text #\newline))
         ;; A chunk usually ends with a newline, which string-split turns into a
         ;; trailing empty element; dropping it avoids a blank log line per read.
         (lines (if (and (pair? lines) (string-null? (last lines)))
                    (drop-right lines 1)
                    lines)))
    (for-each
     (lambda (line)
       (format log-port "~a ~a ~a\n" direction (clock-now) line))
     lines)
    (force-output log-port)))

(define (pump client repl log-port)
  "Forward bytes between CLIENT and REPL until both directions are closed.

Half-close is the whole difficulty. A client like `nc -N' shuts down its write
side as soon as its stdin hits EOF, which surfaces here as EOF when reading
CLIENT -- while the REPL has not yet sent its reply. Tearing the connection down
at that point loses the answer, so an EOF retires one *direction*: we pass it
upstream with shutdown so the REPL sees end-of-input, stop reading that side, and
keep forwarding the other until it closes too."
  ;; Without this the ports hand back a byte at a time and every character
  ;; becomes its own transcript line.
  (setvbuf client 'block 65536)
  (setvbuf repl 'block 65536)
  (let loop ((readers (list client repl)))
    (unless (null? readers)
      (let ((ready (car (select readers '() '() 300))))
        (if (null? ready)
            (begin
              (format log-port "!! ~a idle for 300s, closing\n" (clock-now))
              (force-output log-port))
            (let ((retired '()))
              (for-each
               (lambda (port)
                 (let ((bv (get-bytevector-some port)))
                   (if (eof-object? bv)
                       (let ((peer (if (eq? port client) repl client)))
                         (format log-port "-- ~a ~a sent eof\n" (clock-now)
                                 (if (eq? port client) "client" "repl"))
                         (force-output log-port)
                         ;; Tell the peer no more input is coming, so it can
                         ;; finish its reply and close in turn.
                         (false-if-exception (shutdown peer 1))
                         (set! retired (cons port retired)))
                       (let ((peer (if (eq? port client) repl client))
                             (direction (if (eq? port client) "->" "<-")))
                         (log-chunk log-port direction bv)
                         (catch #t
                           (lambda ()
                             (put-bytevector peer bv)
                             (force-output peer))
                           (lambda args
                             (format log-port "!! ~a write to peer failed: ~s\n"
                                     (clock-now) args)
                             (force-output log-port)
                             (set! retired (cons port retired))))))))
               ready)
              (loop (lset-difference eq? readers retired))))))))

(define (serve listen-port target-port log-file)
  (mkdir-p (dirname log-file))
  (rotate-logs! log-file)
  (let ((log-port (open-file log-file "a"))
        (listener (socket PF_INET SOCK_STREAM 0)))
    (setsockopt listener SOL_SOCKET SO_REUSEADDR 1)
    ;; Bind must fail loudly. SO_REUSEADDR does not let two processes listen on
    ;; one port, so a stale proxy from an earlier session silently keeps this
    ;; one from ever seeing a connection -- and its transcript lands in the old
    ;; log file, which reads as "the proxy logged nothing". See EXPERIMENTS.org.
    (catch 'system-error
      (lambda () (bind listener AF_INET INADDR_LOOPBACK listen-port))
      (lambda args
        (format (current-error-port)
                "repl-proxy: cannot bind 127.0.0.1:~a -- ~a\n"
                listen-port (strerror (system-error-errno args)))
        (format (current-error-port)
                "  another proxy is probably still running; check with:\n")
        (format (current-error-port)
                "    pgrep -fl repl-proxy\n")
        (exit 1)))
    (listen listener 5)
    (format log-port "\n;; session ~a  proxy ~a -> repl ~a\n"
            (iso-8601-now) listen-port target-port)
    (force-output log-port)
    (format (current-error-port)
            "repl-proxy: 127.0.0.1:~a -> 127.0.0.1:~a, logging to ~a\n"
            listen-port target-port log-file)

    (let accept-loop ((n 1))
      (let* ((accepted (accept listener))
             (client (car accepted)))
        (format log-port ";; connection ~a at ~a\n" n (iso-8601-now))
        (force-output log-port)
        ;; One upstream connection per client connection: the REPL keeps state
        ;; per connection, so reusing one would leak bindings between clients.
        (catch #t
          (lambda ()
            (let ((repl (socket PF_INET SOCK_STREAM 0)))
              (connect repl AF_INET INADDR_LOOPBACK target-port)
              (pump client repl log-port)
              (close-port repl)))
          (lambda args
            (format log-port "!! ~a cannot reach repl on ~a: ~s\n"
                    (clock-now) target-port args)
            (force-output log-port)
            (format (current-error-port)
                    "repl-proxy: no REPL on port ~a -- is it started?\n"
                    target-port)))
        (close-port client)
        ;; Between connections, never mid-transcript.
        (rotate-logs! log-file)
        (accept-loop (+ n 1))))))

(define option-spec
  '((listen (value #t) (required? #t))
    (target (value #t) (required? #t))
    (log    (value #t) (required? #t))
    (help   (single-char #\h) (value #f))))

(define (main args)
  (let* ((options (getopt-long args option-spec)))
    (when (option-ref options 'help #f)
      (display "usage: guile-repl-proxy.scm --listen PORT --target PORT --log FILE\n")
      (exit 0))
    (serve (string->number (option-ref options 'listen #f))
           (string->number (option-ref options 'target #f))
           (option-ref options 'log #f))))

(main (command-line))
