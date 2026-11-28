#!/usr/bin/env bash
# HUD 0.3.3: the HOOKED u.applyLanes of the DiPO bridge result, run for real (ART on the Mac emulator, dalvikvm) with doubles for the iAP2 message and the cluster service.
#   bash apps/jmk-autoplay-hud/test/hooked/run-hooked.sh [<hooked result dex> <0.3.2 result dex without the hook>]
# The two dex files come as arguments or from JMK_HOOK_DEX and JMK_BASE_DEX (the 0.3.3 bridge result and the 0.3.2 one, as the delta maker built them). Needs adb with an
# emulator (tools/mac-sim) and the Android SDK (platforms/android-19, build-tools 35 d8); without them or without the two files: "skip", exit 0.
#   structured groups   the old path: the hooked dex gives the same frames as the 0.3.2 dex
#   raw blobs           the same frame as the structured path for the same lanes (also with the param's own header in front)
#   a bad blob          nothing sent, nothing thrown;  an empty message: as before;  cpLane giving null or throwing: nothing thrown, the lanes are still sent
here="$(cd "$(dirname "$0")" && pwd)"
HOOK=${1:-${JMK_HOOK_DEX:-}}; BASE=${2:-${JMK_BASE_DEX:-}}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}; platform=$sdk/platforms/android-19/android.jar; d8=$sdk/build-tools/35.0.0/d8
dev=$(adb devices 2>/dev/null | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}')
[ -n "$dev" ] && [ -f "$platform" ] && [ -x "$d8" ] && [ -f "$HOOK" ] && [ -f "$BASE" ] || { echo "skip: no emulator / SDK / result dex (hooked-applyLanes test not run)"; exit 0; }
W=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hooked.XXXXXX"); trap 'rm -rf "$W"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$W/c" $(find "$here/src" -name '*.java') || { echo "FAIL the doubles do not compile"; exit 1; }
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$W/n" $(find "$here/nullleafia" -name '*.java') || { echo "FAIL the null LeafiaLane does not compile"; exit 1; }
(cd "$W/c" && jar cf "$W/test.jar" .) && (cd "$W/n" && jar cf "$W/null.jar" .)
mkdir -p "$W/t" "$W/n2"; "$d8" --min-api 19 --lib "$platform" --output "$W/t" "$W/test.jar" >/dev/null 2>&1 && "$d8" --min-api 19 --lib "$platform" --output "$W/n2" "$W/null.jar" >/dev/null 2>&1 || { echo "FAIL d8"; exit 1; }
mkjar() { cp "$1" "$W/classes.dex"; (cd "$W" && rm -f "$2" && zip -q "$2" classes.dex); }
mkjar "$HOOK" hook.jar; mkjar "$BASE" base.jar; cp "$W/t/classes.dex" "$W/classes.dex"; (cd "$W" && zip -q testd.jar classes.dex); cp "$W/n2/classes.dex" "$W/classes.dex"; (cd "$W" && zip -q nulld.jar classes.dex)
T=/data/local/tmp/jmkhooked; adb -s "$dev" shell "mkdir -p $T" >/dev/null 2>&1
for f in hook base testd nulld; do adb -s "$dev" push "$W/$f.jar" $T/$f.jar >/dev/null 2>&1; done
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }; fail() { echo "FAIL  $1"; FAILN=$((FAILN + 1)); }
run() { adb -s "$dev" shell "CLASSPATH=$1 app_process /system/bin jmktest.HookTest $2 2>/dev/null" | tr -d '\r' | grep -E '^(FRAMES|FRAME |THROW)'; }   # run <class path> <scenario>
frames() { grep '^FRAME ' | sort; }
for sc in structA structB structEmpty; do
    h=$(run $T/hook.jar:$T/testd.jar $sc); b=$(run $T/base.jar:$T/testd.jar $sc)
    [ -n "$b" ] && [ "$h" = "$b" ] && ok "$sc: the hooked dex gives exactly the 0.3.2 dex's frames ($(echo "$h" | head -1))" || fail "$sc: hooked '$h' vs 0.3.2 '$b'"
done
s=$(run $T/hook.jar:$T/testd.jar structA | frames); r=$(run $T/hook.jar:$T/testd.jar rawA | frames)
[ -n "$s" ] && [ "$s" = "$r" ] && ok "rawA: the raw blobs give the same frame as the structured groups for the same three lanes" || fail "rawA frame '$r' vs structured '$s'"
r=$(run $T/hook.jar:$T/testd.jar rawAhdr | frames); [ -n "$s" ] && [ "$s" = "$r" ] && ok "rawAhdr: blobs with the param's own header in front give the same frame (layout b)" || fail "rawAhdr '$r'"
s=$(run $T/hook.jar:$T/testd.jar structB | frames); r=$(run $T/hook.jar:$T/testd.jar rawB | frames)
[ -n "$s" ] && [ "$s" = "$r" ] && ok "rawB: two other lanes (status 2, repeated angles): the same frame as structured" || fail "rawB frame '$r' vs structured '$s'"
bad=$(run $T/hook.jar:$T/testd.jar rawBad)
[ "$(echo "$bad" | grep -c '^FRAMES 0$')" = 1 ] && [ "$(echo "$bad" | grep -c THROW)" = 0 ] && ok "rawBad: a truncated blob: nothing sent, nothing thrown" || fail "rawBad: '$bad'"
e=$(run $T/hook.jar:$T/testd.jar rawEmpty); se=$(run $T/hook.jar:$T/testd.jar structEmpty)
[ -n "$e" ] && [ "$e" = "$se" ] && ok "rawEmpty: a message with no lane blob behaves like one with no lane groups" || fail "rawEmpty '$e' vs '$se'"
n=$(run $T/nulld.jar:$T/hook.jar:$T/testd.jar nullCp)
[ "$(echo "$n" | grep -c THROW)" = 0 ] && [ "$(echo "$n" | grep -c '^FRAMES')" = 1 ] && ok "nullCp: cpLane giving null: no exception ($(echo "$n" | head -1))" || fail "nullCp: '$n'"
n=$(run $T/nulld.jar:$T/hook.jar:$T/testd.jar throwCp)
[ "$(echo "$n" | grep -c THROW)" = 0 ] && [ "$(echo "$n" | grep -c '^FRAMES')" = 1 ] && ok "throwCp: cpLane throwing: no exception out of applyLanes ($(echo "$n" | head -1))" || fail "throwCp: '$n'"
adb -s "$dev" shell "rm -rf $T" >/dev/null 2>&1
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
