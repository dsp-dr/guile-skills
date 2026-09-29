;;; init.el --- project-local Emacs profile for guile-skills DX  -*- lexical-binding: t; -*-
;;
;; Launched by scripts/dx.sh as:
;;
;;     emacs -nw --init-directory=<repo>/.dx-emacs
;;
;; and this file is copied in there, so the user's own ~/.emacs.d is never
;; touched, read, or modified. Everything it installs lands in .dx-emacs/elpa/,
;; which is gitignored.
;;
;; Emacs 29 introduced --init-directory; this repo's DX assumes >= 29 and
;; scripts/dx.sh asserts it rather than letting a silent fallback load the user's
;; real configuration.

;;; Code:

;; Anchor the profile to THIS file's directory, whatever flags launched Emacs, and
;; pin package.el's paths EXPLICITLY.
;;
;; Setting user-emacs-directory alone is not enough and the failure is silent and
;; bad: `package-user-dir' is a defcustom whose default is computed when package.el
;; loads, and package.el is already loaded (package-activate-all runs during
;; startup) by the time an init file gets a chance to move user-emacs-directory. So
;; the variable pointed at .dx-emacs while package-user-dir still pointed at
;; ~/.emacs.d/elpa -- and this profile installed keycast, compat and cond-let into
;; the USER'S real Emacs directory while claiming not to touch it. Measured
;; 2026-09-29, and the reason these three lines are explicit rather than derived.
(when load-file-name
  (setq user-emacs-directory (file-name-directory load-file-name)))
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory)
      package-gnupghome-dir (expand-file-name "gnupg" package-user-dir)
      package-quickstart nil)

(setq inhibit-startup-screen t
      initial-buffer-choice nil
      ring-bell-function 'ignore
      make-backup-files nil
      auto-save-default nil
      enable-local-variables :all)   ; .dir-locals.el is the point of this profile

;; In a tmux pane every row counts, and the menu bar costs one while telling a
;; capture nothing. The startup screen costs the whole window and sets its own
;; header line, which hides keycast on the one buffer you see first.
(menu-bar-mode -1)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))

(require 'package)
;; All three archives, because the four packages this profile needs are spread
;; across them and the dependency chain crosses archives:
;;
;;   geiser, geiser-guile   NonGNU ELPA (also MELPA)   https://www.nongnu.org/geiser/
;;   paredit                GNU ELPA
;;   keycast                MELPA and NonGNU ELPA      https://github.com/tarsius/keycast
;;   compat, cond-let       GNU ELPA -- keycast's dependencies, and the reason a
;;                          stale archive list makes keycast look unavailable
;;
;; Resolved here: keycast-20260925.1912 from MELPA, compat-31.1.0.0 from GNU ELPA
;; (signed), cond-let from MELPA.
(setq package-archives '(("gnu"    . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa"  . "https://melpa.org/packages/")))

;; Bootstrap, but never fail to start. An offline box should still get a usable
;; editor with scheme-mode; it just will not get Geiser.
(defvar guile-skills-dx-missing nil)

(defun guile-skills-dx-ensure (pkg)
  "Install PKG if absent. Refresh once on failure, then record rather than signal.

The retry is not defensive padding. Refreshing only when
`package-archive-contents' is empty means a STALE cached archive list is treated
as good, and the install then fails on a dependency the archive does have: keycast
needs compat 31.0, and a cached list from an earlier run reported it unavailable
while a refresh showed compat 31.1.0.0 sitting there. Measured 2026-09-29."
  (unless (package-installed-p pkg)
    (dolist (attempt '(:cached :refreshed))
      (unless (package-installed-p pkg)
        (condition-case err
            (progn
              (when (or (eq attempt :refreshed) (null package-archive-contents))
                (package-refresh-contents))
              (package-install pkg))
          (error
           (when (eq attempt :refreshed)
             (push (cons pkg (error-message-string err))
                   guile-skills-dx-missing)))))))
  (package-installed-p pkg))

(package-initialize)

;; Install only when explicitly asked, which is what scripts/dx.sh does in batch
;; BEFORE it opens the interactive session. An interactive editor must never block
;; on the network at startup: the pane just sits there saying "Contacting host",
;; and a capture of it is indistinguishable from a profile that failed to load.
(when (or noninteractive (getenv "DX_INSTALL_PACKAGES"))
  (dolist (pkg '(geiser geiser-guile paredit keycast))
    (guile-skills-dx-ensure pkg)))

;; Installed is not loaded: geiser-guile is autoloaded, so (featurep 'geiser-guile)
;; stays nil until something pulls it in, and every check below would report it
;; absent while it sat in elpa/. Require it once, here, and let the checks mean
;; what they say.
(require 'geiser-guile nil t)
(require 'paredit nil t)
(require 'keycast nil t)

;; keycast shows the command each keystroke ran. This is not decoration: the whole
;; verification story here is `tmux capture-pane', and a captured pane otherwise
;; shows the RESULT of a key without showing which key or which command produced
;; it. With keycast the pane is self-describing -- you can see that C-c C-g really
;; invoked guile-skills-dx-connect and not something a local binding shadowed.
;;
;; HEADER line, deliberately, not the default mode line. keycast-mode replaces
;; part of the mode line, where it competes with the buffer name, position and
;; minor modes and gets truncated first in a narrow pane -- and truncated is
;; useless when the point is to read which command ran. The header line is its own
;; row at the TOP of each window, so a capture shows it whole, and it reads as the
;; running checklist for an interactive Emacs + Guile session.
(when (fboundp 'keycast-header-line-mode)
  (keycast-header-line-mode 1))

;; Probe for the interpreter the same way scripts/lib/guile-repl-paths.sh does.
;; Never pin a name: it is guile3 on FreeBSD, guile-3.0 on Debian, guile under
;; Homebrew. guile-cps-debugger's .dir-locals.el pins guile3; that is 8178314 in
;; Emacs form.
(defvar guile-skills-dx-binary
  (seq-find #'executable-find '("guile3" "guile-3.0" "guile"))
  "The Guile 3 binary actually present on this machine.")

(when (featurep 'geiser-guile)
  (setq geiser-guile-binary guile-skills-dx-binary
        geiser-active-implementations '(guile)
        geiser-repl-history-filename
        (expand-file-name "geiser-history" user-emacs-directory)))

(add-hook 'scheme-mode-hook
          (lambda ()
            (when (fboundp 'paredit-mode) (paredit-mode 1))
            (setq-local indent-tabs-mode nil)))

(dolist (form '(match when unless define-module define-public
                with-output-to-port define-record-type))
  (put form 'scheme-indent-function 1))

;; The project's own ports and load path, written by scripts/dx.sh so elisp does
;; not have to re-derive them and disagree with the shell.
(let ((f (expand-file-name "project.el" user-emacs-directory)))
  (when (file-readable-p f) (load f nil t)))

(defun guile-skills-dx-connect ()
  "Connect Geiser to this project's logging proxy port."
  (interactive)
  (cond
   ((not (featurep 'geiser-guile))
    (message "Geiser is not installed: %S" guile-skills-dx-missing))
   ((not (boundp 'guile-skills-dx-proxy-port))
    (message "no project.el; run scripts/dx.sh rather than emacs directly"))
   (t (geiser-connect 'guile "127.0.0.1" guile-skills-dx-proxy-port))))

(global-set-key (kbd "C-c C-g") #'guile-skills-dx-connect)

(with-current-buffer (get-buffer-create "*dx*")
  (insert "guile-skills DX profile\n\n")
  (insert (format "  guile binary   %s\n" (or guile-skills-dx-binary "NOT FOUND")))
  (insert (format "  geiser         %s\n"
                  (if (featurep 'geiser-guile) "loaded"
                    (format "NOT AVAILABLE %S" guile-skills-dx-missing))))
  (insert (format "  paredit        %s\n"
                  (if (fboundp 'paredit-mode) "loaded" "NOT AVAILABLE")))
  (when (boundp 'guile-skills-dx-proxy-port)
    (insert (format "  proxy port     %s   (C-c C-g to connect)\n"
                    guile-skills-dx-proxy-port)))
  (when (boundp 'guile-skills-dx-load-path)
    (insert (format "  load path      %s\n" guile-skills-dx-load-path))))

;;; init.el ends here
