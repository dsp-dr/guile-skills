# guile-skills --- agent skills and tooling for Guile Scheme projects
#
# gmake, not make: these targets assume GNU make.

# FreeBSD ports give guile3/guild3; Debian and Ubuntu give guile-3.0/guild-3.0.
# Probe rather than assume -- gate.yml's first run would otherwise fail on a
# binary name (EXPERIMENTS.org E9 is the same class of mistake).
SERVER_SCRIPTS := skills/guile-repl-server/scripts
EVAL_SCRIPTS   := skills/guile-repl-eval/scripts
PROXY_SCRIPTS  := skills/guile-repl-proxy/scripts

GUILE ?= $(shell command -v guile3 2>/dev/null || command -v guile-3.0 2>/dev/null || echo guile)
GUILD ?= $(shell command -v guild3 2>/dev/null || command -v guild-3.0 2>/dev/null || echo guild)

.PHONY: help start stop status eval lint lint-org lint-claude test check-evals check-monitors check-scripts check-version sync-scripts checks try try-in ship-check readme paths clean release-staging release-production

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
	@echo "  gmake lint-org     org-lint every tracked .org file"
	@echo "  gmake lint-claude  claude plugin validate . --strict"
	@echo "  gmake check-evals  validate every skills/*/evals/evals.json"
	@echo "  gmake check-monitors  validate monitors/monitors.json (the CLI does not)"
	@echo "  gmake sync-scripts  copy scripts/lib/ into each skill that needs it"
	@echo "  gmake check-scripts verify those copies have not drifted"
	@echo "  gmake check-version verify a shipped change raised plugin.json version"
	@echo "  gmake checks   everything CI runs: lint + check-evals + test"
	@echo "  gmake try      open Claude Code with this plugin loaded from the working tree"
	@echo "  gmake try-in DIR=<path>  same, but with the cwd in another project"
	@echo "  gmake ship-check  show exactly which files an install actually delivers"
	@echo "  gmake readme   regenerate the generated .md docs from their .org sources"
	@echo "  gmake clean    remove compiled files"
	@echo "  gmake release-staging              regression tests + validation, no publish"
	@echo "  gmake release-production TAG=vX.Y.Z   same gate, then gh skill publish --tag"

start:
	@$(SERVER_SCRIPTS)/guile-repl-server.sh

stop:
	@$(SERVER_SCRIPTS)/guile-repl-server.sh --stop

status:
	@$(SERVER_SCRIPTS)/guile-repl-server.sh --status

paths:
	@$(SERVER_SCRIPTS)/guile-repl-paths.sh

eval:
ifndef F
	$(error F is required. Usage: gmake eval F='(+ 1 1)')
endif
	@$(EVAL_SCRIPTS)/guile-repl-eval.sh '$(F)'

# guild writes a temp file and renames it, so -o /dev/null always fails
# (EXPERIMENTS.org E7). Compile to a real path and keep only the warnings.
lint:
	@mkdir -p .logs
	@if command -v $(GUILD) >/dev/null 2>&1; then \
		$(GUILD) compile -W 3 -o .logs/lint.go $(PROXY_SCRIPTS)/guile-repl-proxy.scm 2>&1 \
			| grep -iE 'warning|error' || true; \
	else \
		echo "lint: no guild on PATH; skipping Scheme warnings (shell checks still run)"; \
	fi
	@for s in scripts/*.sh scripts/lib/*.sh skills/*/scripts/*.sh; do sh -n "$$s" || exit 1; done
	@echo "Lint complete."

test:
	@./tests/test-proxy.sh

# Tracked .org files only, so a stray scratch file in the tree is not linted.
ORG_FILES := $(shell git ls-files '*.org' 2>/dev/null)

lint-org:
	@command -v emacs >/dev/null 2>&1 || { echo "lint-org: emacs is not on PATH; skipping"; exit 0; }
	@emacs -Q --batch -l tests/org-lint.el $(ORG_FILES)

lint-claude:
	@command -v claude >/dev/null 2>&1 || { echo "lint-claude: the Claude Code CLI is not on PATH; skipping"; exit 0; }
	@claude plugin validate . --strict

check-evals:
	@python3 ./tests/validate-evals.py

# `claude plugin validate' does not read monitors/monitors.json -- measured
# 2026-09-29, at the default path and declared explicitly, with and without
# --strict: an unknown key, a missing description and a bogus `when' all passed.
# The reference says an unknown key inside an entry stops the plugin loading, so
# this is the check that can actually fail.
check-monitors:
	@python3 ./tests/validate-monitors.py

# scripts/lib/ is canonical; skills/*/scripts/ copies are generated, because a
# skill installed on its own must carry everything it runs.
sync-scripts:
	@./scripts/sync-skill-scripts.sh

check-scripts:
	@./scripts/sync-skill-scripts.sh --check

# A change to what users receive needs a version bump, or every existing
# install silently stays on the old copy. BASE defaults to the newest tag.
check-version:
	@./scripts/check-version-bump.sh $${BASE:-$$(git describe --tags --abbrev=0)}

# What CI runs, in the order that fails cheapest first. `claude plugin validate'
# is deliberately not here: it needs the Claude Code CLI, which CI installs and
# a developer already has running.
checks: lint lint-org lint-claude check-scripts check-version check-evals check-monitors test

# Manual testing. `checks' proves the code is sound; these prove the *plugin*
# works, which is a different question -- the skills reference scripts by path,
# and a path that resolves here may resolve nowhere else.

try:
	@command -v claude >/dev/null 2>&1 || { echo "try: the Claude Code CLI is not on PATH" >&2; exit 1; }
	@echo "loading $(CURDIR) as a plugin; ask it to start a Guile REPL"
	@claude --plugin-dir $(CURDIR)

# The test that matters: plugin from here, working directory somewhere else.
# Anything in a SKILL.md written as ./bin/... breaks here and only here.
try-in:
ifndef DIR
	$(error DIR is required. Usage: gmake try-in DIR=$$HOME/ghq/github.com/dsp-dr/guile-sicp)
endif
	@test -d "$(DIR)" || { echo "try-in: no such directory: $(DIR)" >&2; exit 1; }
	@echo "cwd $(DIR), plugin $(CURDIR)"
	@cd "$(DIR)" && claude --plugin-dir $(CURDIR)

# What a user actually receives. `gh skill install' copies skills/<name>/** and
# nothing else, so this is how you find out that a script did not ship.
ship-check:
	@./scripts/ship-check.sh

GENERATED_DOCS := README.md CONTRIBUTING.md

# Org is the authored form for every document here; the .md files below are
# generated projections, never edited by hand. README.md exists because the
# plugin directory requires a README in the plugin folder, "preferably named
# README.md", and shows it as the listing description. CONTRIBUTING.md exists
# because GitHub surfaces it in the repository's "Contributing guidelines"
# affordance and does not recognise CONTRIBUTING.org there.
# Both are committed, because GitHub renders the .md and the directory listing
# reads it. Edit the .org.
#
# CI ignores changes to either file (paths-ignore in .github/workflows/*.yml),
# so a README-only commit does not spend a runner. For a mixed commit that
# should still skip, put [skip ci] in the commit message -- GitHub Actions
# honours that natively and paths-ignore will not, since paths-ignore only
# skips when *every* changed path matches.
readme: $(GENERATED_DOCS)

# One rule for every generated doc. A .md target fires it only when that .md is
# asked for, so EXPERIMENTS.org and the rest stay org-only.
%.md: %.org
	@command -v pandoc >/dev/null 2>&1 || { \
		echo "readme: pandoc is required (pkg install hs-pandoc, or brew install pandoc)" >&2; \
		exit 1; \
	}
	@printf '<!-- Generated from $< by `gmake readme`. Edit the .org, not this file. -->\n\n' > $@
	@printf '# %s\n\n' "$$(sed -n 's/^\#+TITLE: *//p' $<)" >> $@
	@pandoc -f org -t gfm --wrap=none --shift-heading-level-by=1 $< \
		| sed -e 's|](file:|](|g' \
		      -e 's|^``` \([a-z]\)|```\1|' >> $@
	@echo "wrote $@ from $< ($$(wc -l < $@ | tr -d ' ') lines)"

clean:
	@rm -rf .logs
	@find . -name '*.go' -not -path './.git/*' -delete
	@find . -name '*~' -not -path './.git/*' -delete
	@echo "Cleaned."

release-staging:
	@./scripts/release.sh staging

release-production:
ifndef TAG
	$(error TAG is required. Usage: gmake release-production TAG=v0.1.0)
endif
	@./scripts/release.sh production $(TAG)
