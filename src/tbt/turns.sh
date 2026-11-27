#!/usr/bin/env bash
# 0.1.34: a result dex of 0.1.33 (HKMC_GPM or the HKMC_DiPO bridge build) -> the same build whose turn pictures (far
# icon and near layout) follow the stock Korean numbers (com/jmk/hud/Turns.java decides, TurnsOut.java is the hooks'
# side; hooks in turns.py):
#   src/tbt/turns.sh <gpm|dipo> <0.1.33 result dex> <out dex>
#     gpm:  3acf3d096ee019acc1632e83a01feab2 -> see README (0.1.34)      (every Korean profile's GPM)
#     dipo: c9754d6f6dc75d4029ef6c9fdf88389c -> see README (0.1.34)      (the DiPO bridge build)
# Steps: javac (Java 7 classes, against the Android 19 jar; Near.java of src/tbt/bar is only compiled against, the
# result keeps the Near it has) + the Android SDK's d8 (--min-api 19) build Turns and TurnsOut; baksmali 2.5.2 (-a 19)
# takes both dexes apart; turns.py edits the tree (status 1 when a hook point is not found exactly once); smali 2.5.2
# (-a 19, one thread: the same input gives the same bytes) puts it back together. Needs a JDK, ANDROID_HOME (or
# ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, python3, and the smali / baksmali 2.5.2 jars
# (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 3 ] || { sed -n '2,7p' "$0"; exit 2; }
kind=$1; base=$2; out=$3
case "$kind" in
    gpm|dipo) ;;
    *) sed -n '2,7p' "$0"; exit 2 ;;
esac
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" \
    "$here/turns/com/jmk/hud/Turns.java" "$here/turns/com/jmk/hud/TurnsOut.java" "$here/bar/com/jmk/hud/Near.java"
rm -f "$work"/classes/com/jmk/hud/Near*.class
(cd "$work/classes" && jar cf "$work/turns.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/turns.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/turns.py" "$kind" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
