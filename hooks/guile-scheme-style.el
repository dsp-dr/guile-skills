;;; guile-scheme-style.el --- the one Scheme style every tool here uses  -*- lexical-binding: t; -*-
;;
;; Loaded by BOTH the batch tools and the interactive profile, so an edit made by
;; `gmake fmt' and an edit made by hand in Emacs indent the same way. Before this
;; existed, hooks/scheme-indent.el and emacs/init.el each carried their own list of
;; forms and their own indent-tabs-mode, which is a drift waiting to happen: the
;; formatter would reindent what the editor had just indented differently.
;;
;; The file name matches the feature it provides, because `require' searches
;; load-path for a file named after the FEATURE -- naming it scheme-style.el while
;; providing guile-scheme-style made every tool that required it fail.
;;
;; It lives in hooks/ rather than emacs/ because hooks/ is what a plugin install
;; delivers -- the hook has to work on a machine that never sees this repository's
;; emacs/ directory. The interactive profile loads it from here by relative path.
;;
;; Nothing in here is Guile-version specific and nothing probes the filesystem, so
;; it is safe to load in --batch and in an interactive session alike.

(require 'scheme)

(defconst guile-scheme-indent-1-forms
  '(match when unless define-module define-public define-record-type
    with-output-to-port with-input-from-port with-error-to-port
    let-values let*-values call-with-values syntax-rules
    call-with-output-string call-with-input-string
    with-exception-handler dynamic-wind)
  "Forms whose body indents by one, beyond what `scheme-mode' knows.
Kept deliberately short: every entry is a form that appears in this corpus, and a
speculative list is worse than none because it silently reindents code nobody
here writes.")

(defun guile-scheme-apply-style ()
  "Apply this project's Scheme conventions to the current buffer.
Call after `scheme-mode'."
  (setq-local indent-tabs-mode nil)     ; tabs in Scheme are a diff hazard
  (setq-local fill-column 80)
  (dolist (form guile-scheme-indent-1-forms)
    (put form 'scheme-indent-function 1)))

(provide 'guile-scheme-style)
;;; guile-scheme-style.el ends here
