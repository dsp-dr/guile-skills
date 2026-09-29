;;; scheme-indent.el --- batch Scheme balance check and reindent  -*- lexical-binding: t; -*-
;;
;; Emacs is the formatter here because there is no standalone one. Probed on
;; nexus 2026-09-29: scmindent, lispindent and schemefmt are all absent, and
;; `guild' compiles but does not format. Emacs' scheme-mode has the indentation
;; rules already, so this wraps what is installed rather than adding a dependency.
;;
;;   emacs --batch -Q -l scheme-indent.el -- --check  FILE...   ; report only
;;   emacs --batch -Q -l scheme-indent.el -- --write  FILE...   ; reindent in place
;;
;; Exit 3 on an unbalanced file, 0 otherwise. --check never writes.

(require 'scheme)

;; One style, shared with the interactive profile. See hooks/scheme-style.el for
;; why it is not duplicated here.
(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name
                                                 default-directory)))
(require 'guile-scheme-style)

(let* ((args (cdr (member "--" command-line-args)))
       (mode (car args))
       (files (cdr args))
       (bad 0))
  (unless (member mode '("--check" "--write"))
    (princ "usage: -- --check|--write FILE...\n")
    (kill-emacs 2))
  (dolist (f files)
    (when (file-readable-p f)
      (with-temp-buffer
        (insert-file-contents f)
        (scheme-mode)
        (guile-scheme-apply-style)
        (condition-case err
            (check-parens)
          (error
           ;; check-parens leaves point at the offence, which is the only part of
           ;; this that a person actually needs.
           (princ (format "%s:%d: %s\n" f (line-number-at-pos)
                          (error-message-string err)))
           (setq bad (1+ bad))))
        (when (and (= bad 0) (string= mode "--write"))
          (let ((before (buffer-string)))
            (indent-region (point-min) (point-max))
            (delete-trailing-whitespace)
            (unless (string= before (buffer-string))
              (write-region (point-min) (point-max) f nil 'quiet)
              (princ (format "reindented %s\n" f))))))))
  (kill-emacs (if (> bad 0) 3 0)))

;;; scheme-indent.el ends here
