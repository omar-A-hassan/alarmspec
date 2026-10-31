#!/bin/sh
# Checks that the reference design satisfies each requirement, and that each injected
# fault violates the requirement it targets. A requirement that no fault can violate is
# vacuous. Then runs the recall scripts and the two conformance tests.
set -u
cd "$(dirname "$0")"
JAVA=${JAVA:-java}
META=${TMPDIR:-/tmp}/alarm-refmodel-tlc

tlc() { "$JAVA" -XX:+UseParallelGC -cp tools/tla2tools.jar tlc2.TLC -noGenerateSpecTE \
          -workers auto -metadir "$META" -config "$1" MC.tla 2>&1; }

status=0

# Make the model instance (MC.tla, MC.cfg, Recalls.cfg) from alarm.toml, and download the
# TLA+ tools if tools/ does not contain them. The checks in this script always use alarm.toml.
export ALARM_CONFIG=alarm.toml
uv run --no-project python -c 'import conformance; conformance.write_instance("."); conformance.tla_jar()' || exit 1

# Copy the constants and the specification from a .cfg file. Check TypeOK and one
# requirement only.
only() {
    sed '/^INVARIANTS/,$d'
    case "$1" in
        PauseEnds|RemindWhileOff) printf 'INVARIANTS\n    TypeOK\nPROPERTIES\n    %s\n' "$1" ;;
        *)                        printf 'INVARIANTS\n    TypeOK\n    %s\n' "$1" ;;
    esac
}

if tlc MC.cfg | grep -q "No error has been found"; then
    echo "PASS  reference design"
else
    echo "FAIL  reference design"; tlc MC.cfg | tail -40; status=1
fi

for case in NO_LATCH:LatchHolds LATCH_ALL:NoStaleSignal PAUSE_HIDES_VISUAL:Visible \
            MEDIUM_SILENT:Audible GLOBAL_PAUSE:NewHighBreaksPause \
            STICKY_PAUSE_SET:NewHighBreaksPause ENDLESS_PAUSE:PauseEnds \
            ACK_ALL:Audible ACK_STICKY:Audible ACK_HIDES:Visible \
            ESC_KEEPS_ACK:Audible ESC_KEEPS_PAUSE:NewHighBreaksPause \
            NO_REMINDER:RemindWhileOff FIFO_TONE:ToneIsTop LATCH_SILENT:LatchSounds \
            EDGE_TRIGGERED:Visible PERSIST_SILENCE:LiveAfterBoot NO_ESCALATION:EscalatesOnTime; do
    fault=${case%%:*}; prop=${case#*:}
    only "$prop" < MC.cfg | sed "s/Fault = \"NONE\"/Fault = \"$fault\"/" > .fault.cfg
    out=$(tlc .fault.cfg)
    if echo "$out" | grep -qE "(Invariant|Temporal property) $prop (is|was) violated"; then
        echo "PASS  $fault caught by $prop"
    else
        echo "FAIL  $fault not caught by $prop"; echo "$out" | grep -E "Error|violated" | head -5; status=1
    fi
done

rm -f .fault.cfg

# Recall scripts: the reference design must pass each script, and the named fault must
# violate the named requirement. Format: script:start:LowAudible:fault:requirement
for case in DragerEscalates:NoneActive:FALSE:ESC_KEEPS_PAUSE:NewHighBreaksPause \
            DragerSeparate:NoneActive:FALSE:GLOBAL_PAUSE:NewHighBreaksPause \
            TerumoTransient:NoneActive:FALSE:NO_LATCH:LatchHolds \
            TerumoTransient:NoneActive:FALSE:LATCH_SILENT:LatchSounds \
            GEMasking:NoneActive:TRUE:FIFO_TONE:ToneIsTop \
            InnokasStartup:InnokasStart:FALSE:EDGE_TRIGGERED:Visible \
            RadiometerRestart:NoneActive:FALSE:PERSIST_SILENCE:LiveAfterBoot \
            SpacelabsEscalation:NoneActive:FALSE:NO_ESCALATION:EscalatesOnTime; do
    IFS=: read -r script start low fault prop <<EOF
$case
EOF
    replay() { { if [ "$1" = NONE ]; then cat Recalls.cfg; else only "$prop" < Recalls.cfg; fi; } |
               sed -e "s/SCRIPT/$script/" -e "s/STARTACTIVE/$start/" -e "s/LOWAUDIBLE/$low/" -e "s/Fault = \"NONE\"/Fault = \"$1\"/" \
                   > .recall.cfg
               "$JAVA" -XX:+UseParallelGC -cp tools/tla2tools.jar tlc2.TLC -noGenerateSpecTE -workers 1 \
                   -metadir "$META" -config .recall.cfg MCRecalls.tla 2>&1; }
    if replay NONE | grep -q "No error has been found" &&
       replay "$fault" | grep -qE "Invariant $prop is violated"; then
        echo "PASS  recall $script: reference holds, $fault breaks $prop"
    else
        echo "FAIL  recall $script with $fault/$prop"; replay NONE | grep -E "Error|Deadlock" | head -3; status=1
    fi
done
rm -f .recall.cfg

# The C implementation must agree with the model in each reachable state and on each
# transition.
JAVA="$JAVA" uv run --no-project python conformance.py || status=1

# The black-box test must pass the reference implementation through its adapter.
JAVA="$JAVA" uv run --no-project python blackbox.py testkit/adapter_alarm.c alarm.c || status=1

exit $status
