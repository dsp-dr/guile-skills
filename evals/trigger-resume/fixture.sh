#!/bin/sh
# A small Guile project in the run's empty workspace: modules under irc/, not src/.
set -eu
mkdir -p irc tests
printf '(define-module (irc irc)\n  #:export (connect))\n(define (connect host) host)\n' > irc/irc.scm
printf 'all:\n\tguild compile irc/irc.scm\n' > Makefile
