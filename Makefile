# guile-skills --- agent skills and tooling for Guile Scheme projects
#
# gmake, not make: these targets assume GNU make.

# FreeBSD ports give guile3/guild3; Debian and Ubuntu give guile-3.0/guild-3.0.
# Probe rather than assume -- gate.yml's first run would otherwise fail on a
# binary name (EXPERIMENTS.org E9 is the same class of mistake).
GUILE ?= $(shell command -v guile3 2>/dev/null || command -v guile-3.0 2>/dev/null || echo guile)
GUILD ?= $(shell command -v guild3 2>/dev/null || command -v guild-3.0 2>/dev/null || echo guild)

.PHONY: help start stop status eval lint test check-evals checks paths clean release-staging release-production

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
	@echo "  gmake check-evals  validate every skills/*/evals/evals.json"
	@echo "  gmake checks   everything CI runs: lint + check-evals + test"
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
	@if command -v $(GUILD) >/dev/null 2>&1; then \
		$(GUILD) compile -W 3 -o .logs/lint.go bin/guile-repl-proxy.scm 2>&1 \
			| grep -iE 'warning|error' || true; \
	else \
		echo "lint: no guild on PATH; skipping Scheme warnings (shell checks still run)"; \
	fi
	@for s in bin/*.sh admin/*.sh; do sh -n "$$s" || exit 1; done
	@echo "Lint complete."

test:
	@./tests/test-proxy.sh

check-evals:
	@python3 ./tests/validate-evals.py

# What CI runs, in the order that fails cheapest first. `claude plugin validate'
# is deliberately not here: it needs the Claude Code CLI, which CI installs and
# a developer already has running.
checks: lint check-evals test

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
