#!/bin/sh
# Sensitivity test of the two conformance tests. Each mutant is one fault in a copy of
# alarm.c. conformance.py (white-box) and blackbox.py (through testkit/adapter.h) must
# both fail on each mutant. A mutant that passes shows code that a test cannot see.
# The script runs TLC two times for each mutant, so check.sh does not include it.
set -u
cd "$(dirname "$0")"
JAVA=${JAVA:-java}
status=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

mutant() {  # name, perl substitution applied to a copy of alarm.c
    rm -rf "$work/m"; mkdir "$work/m"
    cp -R AlarmSystem.tla alarm.toml alarm.h alarm.c conformance.py blackbox.py testkit tools "$work/m/"
    perl -0pi -e "$2" "$work/m/alarm.c"
    if cmp -s alarm.c "$work/m/alarm.c"; then echo "FAIL  $1: mutation did not apply"; status=1; return; fi
    for check in "conformance.py" "blackbox.py testkit/adapter_alarm.c alarm.c"; do
        (cd "$work/m" && JAVA="$JAVA" uv run --no-project python $check) > "$work/out" 2>&1
        if grep -q '^FAIL' "$work/out"; then   # a compile error is not a kill
            echo "PASS  $1 killed by ${check%% *}: $(tail -1 "$work/out")"
            [ "${check%% *}" = blackbox.py ] && grep -m1 '^FAIL  ' "$work/out" | cut -c1-220
        else
            echo "FAIL  $1 survived ${check%% *}"; tail -3 "$work/out"; status=1
        fi
    done
}

mutant esc_keeps_ack       's/s->acked &= ~BIT\(c\);(      \/\* escalation)/$1/'
mutant tone_tiebreak       's/eff\(s, c\) > eff\(s, s->tone\)/eff(s, c) >= eff(s, s->tone)/'
mutant init_drops_present  's/    s->worse = 0;\n    s->latched = s->active & s->latching;/    s->active = s->worse = 0;\n    s->latched = 0;/'
mutant power_keeps_pause   's/(alarm_power_cycle\(alarm_sys \*s\)\n\{\n)    s->inact = ALARM_INACT_NONE;\n    s->timer = 0;\n/$1/'
mutant escalate_late       's/\+\+s->age\[c\] >= s->escalate_ticks/++s->age[c] > s->escalate_ticks/'

exit $status
