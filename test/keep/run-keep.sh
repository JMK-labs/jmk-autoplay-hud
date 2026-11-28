#!/usr/bin/env bash
# The Keep / EndLog / Evt (0.3.2) and RawLanes (0.3.3) JVM cases of HUD 0.3.2 on their own (the same ones test/check-scripts.sh runs): core absent / late / gated → the display stays;
# the core's drop and the cause of each end; a restart asks once; the counting lines. Needs javac and java (Java 7 class level).
#   bash apps/jmk-autoplay-hud/test/keep/run-keep.sh
here="$(cd "$(dirname "$0")" && pwd)"; P="$(cd "$here/../.." && pwd)"
KT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-keep.XXXXXX"); trap 'rm -rf "$KT"' EXIT
javac -source 7 -target 7 -Xlint:-options -d "$KT" $(find "$here/stub" -name '*.java') $(find "$P/src/callout/jmkhud/link" -name '*.java' | grep -v '/android/') \
    "$P/src/tbt/com/jmk/hud/Keep.java" "$P/src/tbt/com/jmk/hud/EndLog.java" "$P/src/tbt/com/jmk/hud/Evt.java" "$here/KeepTest.java" "$here/EndLogTest.java" "$here/EvtTest.java" 2>/dev/null \
    || { echo "FAIL the sources do not compile"; exit 1; }
rc=0; n=0
for sc in none late latekeep latestale again againdrop gate separate restart restartkeep restartnone keep drop refresh refreshrecheck norefresh silence recheck busy notes; do
    out=$(java -cp "$KT" com.jmk.hud.KeepTest $sc 2>/dev/null | tail -1); n=$((n + 1))
    [ "$out" = "keep: $sc passed" ] || { echo "FAIL keep $sc: $out"; rc=1; }
done
for c in EndLogTest:"endlog: passed" EvtTest:"evt: passed"; do
    out=$(java -cp "$KT" com.jmk.hud.${c%%:*} 2>/dev/null | tail -1); n=$((n + 1))
    [ "$out" = "${c#*:}" ] || { echo "FAIL ${c%%:*}: $out"; rc=1; }
done
RL=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-rawlanes.XXXXXX")
if javac -source 7 -target 7 -Xlint:-options -d "$RL" $(find "$here/../rawlanes/stub" -name '*.java') "$P/src/tbt/com/jmk/hud/RawLanes.java" "$P/src/tbt/com/jmk/hud/Evt.java" "$here/../rawlanes/RawLanesTest.java" 2>/dev/null; then
    out=$(java -cp "$RL" com.jmk.hud.RawLanesTest 2>/dev/null | tail -1); n=$((n + 1))
    [ "$out" = "rawlanes: passed" ] || { echo "FAIL RawLanesTest: $out"; rc=1; }
else echo "FAIL the RawLanes sources do not compile"; rc=1; fi
rm -rf "$RL"
echo "---- $n scenarios, $([ $rc = 0 ] && echo all passed || echo FAILED)"
exit $rc
