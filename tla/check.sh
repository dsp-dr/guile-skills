#!/bin/sh
# Model-check the release labels and the publish pipeline, BOTH directions.
#
#   1. every rule on must pass;
#   2. each rule switched off must violate the invariant named next to it --
#      a rule whose absence breaks nothing is not being tested by the model;
#   3. the rules AS DEPLOYED on main are run once per invariant, to report
#      which guarantees the running system actually has today.
#
# Convention from aygp-dr/standard-change/tla/check.sh. Needs Java and
# tla2tools.jar; set TLA2TOOLS to point elsewhere.
set -eu
JAR="${TLA2TOOLS:-$HOME/ghq/github.com/aygp-dr/tla-plus-tutorial/tla2tools.jar}"
[ -f "$JAR" ] || { echo "tla2tools.jar not found; set TLA2TOOLS" >&2; exit 1; }
cd "$(dirname "$0")"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK" states' EXIT
run() { java -Xmx${TLC_HEAP:-2g} -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers auto -cleanup \
            -metadir "$WORK/meta-$1" "$WORK/$1" 2>&1; }

# variant NAME SED-EXPR [INVARIANT] -> $WORK/NAME.{tla,cfg}; one invariant if named
variant() {
    sed "s/MODULE GuilePublish/MODULE $1/" GuilePublish.tla > "$WORK/$1.tla"
    sed -e "$2" GuilePublish.cfg > "$WORK/$1.cfg"
    if [ -n "${3:-}" ]; then
        awk -v keep="$3" '
            /^INVARIANTS/ { print; print "    TypeOK"; print "    " keep; skip = 1; next }
            skip && /^[A-Z_]+/ { skip = 0 }
            !skip { print }' "$WORK/$1.cfg" > "$WORK/$1.tmp" && mv "$WORK/$1.tmp" "$WORK/$1.cfg"
    fi
}

status=0

variant Positive 's/x/x/'
printf '== positive: every rule on ............................ '
if run Positive | grep -q 'No error has been found'; then echo PASS
else echo FAIL; run Positive | grep -E 'Error|violated' | head -5; status=1; fi

# rule          invariant its absence must break
for pair in \
    StartClearsEnd:EndMeansHeadPassed \
    CurrentHeadOnly:EndMeansHeadPassed \
    GateFailLabel:GateFailureVisible \
    Concurrency:NoTagRace \
    IdempotentDone:NoRedOnPublished \
    ResumeOnRelease:NoFalseGreen \
    PostVerify:NoFalseGreen \
    OutcomeLabel:PublishOutcomeVisible
do
    rule=${pair%%:*}; inv=${pair#*:}
    variant "No$rule" "s/$rule = TRUE/$rule = FALSE/"
    printf '== negative: %-16s must violate %-22s ' "$rule=FALSE" "$inv"
    if run "No$rule" | grep -q "Invariant $inv is violated"; then echo 'FAIL as required'
    else echo "BAD: $rule is not tested by the model"; status=1; fi
done

# What main runs today (after #28): the four publish rules are deployed; the
# three gate rules and the outcome label are not.
DEPLOYED='s/StartClearsEnd = TRUE/StartClearsEnd = FALSE/;s/CurrentHeadOnly = TRUE/CurrentHeadOnly = FALSE/;s/GateFailLabel = TRUE/GateFailLabel = FALSE/;s/OutcomeLabel = TRUE/OutcomeLabel = FALSE/'
echo
echo "== as deployed on main: which guarantees hold today"
for inv in EndMeansHeadPassed NoStuckStart GateFailureVisible NoFalseGreen NoTagRace NoRedOnPublished PublishOutcomeVisible; do
    variant "Dep$inv" "$DEPLOYED" "$inv"
    if run "Dep$inv" | grep -q 'No error has been found'; then r=holds; else r=VIOLATED; fi
    printf '   %-24s %s\n' "$inv" "$r"
done
exit $status
