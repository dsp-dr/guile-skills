;;; org-lint.el --- batch org-lint over the files named on the command line  -*- lexical-binding: t; -*-
;;
;;   emacs -Q --batch -l tests/org-lint.el README.org CONTRIBUTING.org
;;
;; Exit status is 1 only when a `high' trust problem is found. org-lint's `low'
;; trust checks are heuristics, and one of them fires on every mermaid block we
;; ship: "Unknown source block language: 'mermaid'" is correct as far as Babel
;; is concerned and wrong for our purposes, since those blocks exist for
;; GitHub's renderer, not for evaluation. Low-trust findings are printed so a
;; reader can judge them; they do not fail the build.

(require 'org)
(require 'org-lint)

(let ((high 0) (low 0))
  (dolist (file argv)
    (if (not (file-readable-p file))
        (progn (princ (format "  MISS  %s (unreadable)\n" file)) (setq high (1+ high)))
      (with-current-buffer (find-file-noselect file)
        (let ((reports (org-lint--generate-reports (current-buffer) org-lint--checkers)))
          (if (null reports)
              (princ (format "  ok    %s\n" file))
            (princ (format "  %-5s %s\n" (if (seq-some (lambda (r) (equal (aref (cadr r) 1) "high")) reports)
                                             "FAIL" "warn")
                           file))
            (dolist (r reports)
              (let* ((v (cadr r))
                     (line (substring-no-properties (aref v 0)))
                     (trust (aref v 1))
                     (desc (aref v 2)))
                (if (equal trust "high") (setq high (1+ high)) (setq low (1+ low)))
                (princ (format "          %s:%s [%s] %s\n" file line trust desc)))))))))
  (princ (format "\norg-lint: %d high, %d low\n" high low))
  (kill-emacs (if (> high 0) 1 0)))
