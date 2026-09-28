# guile-skills --- agent skills and tooling for Guile Scheme projects
#
# gmake, not make: these targets assume GNU make.

GUILE ?= guile3
GUILD ?= guild3

.PHONY: help start stop status eval lint test paths clean release-staging release-production

help:
	@echo "guile-skills"
	@echo ""
	@echo "  gmake start    start this project's REPL (PORT) and logging proxy (PORT+1)"
	@echo "  gmake status   what is actually listening"
	@echo "  gmake stop     stop both"
	@echo "  gmake eval F='(+ 1 1)'   evaluate through the proxy"
	@echo "  gmake paths    show this project's slug, ports and log directory"
	@echo "  gmake lint     compile every script with warnings"
	@echo "  gmake test     end-to-end proxy tests"
	@echo "  gmake clean    remove compiled files"
	@echo "  gmake release-staging              regression tests + validation, no publish"
	@echo "  gmake release-production TAG=vX.Y.Z   same gate, then gh skill publish --tag"

start:
	@./bin/guile-repl-server.sh

stop:
	@./bin/guile-repl-server.sh --stop

status:
	@./bin/guile-repl-server.sh --status

paths:
	@./bin/guile-repl-paths.sh

eval:
ifndef F
	$(error F is required. Usage: gmake eval F='(+ 1 1)')
endif
	@./bin/guile-repl-eval.sh '$(F)'

# guild writes a temp file and renames it, so -o /dev/null always fails
# (EXPERIMENTS.org E7). Compile to a real path and keep only the warnings.
lint:
	@mkdir -p .logs
	@$(GUILD) compile -W 3 -o .logs/lint.go bin/guile-repl-proxy.scm 2>&1 \
		| grep -iE 'warning|error' || true
	@for s in bin/*.sh; do sh -n "$$s" || exit 1; done
	@echo "Lint complete."

test:
	@./tests/test-proxy.sh

clean:
	@rm -rf .logs
	@find . -name '*.go' -not -path './.git/*' -delete
	@find . -name '*~' -not -path './.git/*' -delete
	@echo "Cleaned."

release-staging:
	@./bin/release.sh staging

release-production:
ifndef TAG
	$(error TAG is required. Usage: gmake release-production TAG=v0.1.0)
endif
	@./bin/release.sh production $(TAG)
