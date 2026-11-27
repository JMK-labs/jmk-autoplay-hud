#!/usr/bin/env bash
# 0.1.33: a result dex of 0.1.32 (HKMC_GPM, the HKMC_DiPO bridge build, or HKMC_Navi_ExSL) -> the same build whose
# cluster near-turn distance bar comes from the phone's guidance (com/jmk/hud/Bar.java, BarOut.java, NaviBar.java and
# Near.java extended to the stock distance D; hooks in bar.py):
#   src/tbt/bar.sh <gpm|dipo|navi> <0.1.32 result dex> <out dex>
#     gpm:  d2538947dcd6a8af532e0fb2baf7be81 -> see README (0.1.33)      (every Korean profile's GPM)
#     dipo: e1d75f6d58f337d8dfe5e32d937225c9 -> see README (0.1.33)      (the DiPO bridge build)
#     navi: 77980719134a05eea6d784b2113e651f / 44b26803ee61ee5f168466590189396f / ... -> see README (0.1.33)
# gpm and dipo carry Near.java of src/tbt/bar (Near.smali of the input is replaced by it: same entry points, the window
# is D); navi carries Bar, BarOut and NaviBar. Steps: javac (Java 7 classes, against the Android 19 jar) + the Android
# SDK's d8 (--min-api 19) build the classes; baksmali 2.5.2 (-a 19) takes both dexes apart (the new classes overwrite
# an older com/jmk/hud/Near*.smali); bar.py edits the tree (status 1 when a hook point is not found exactly once);
# smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it back together. Needs a JDK, ANDROID_HOME
# (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, python3, and the smali / baksmali 2.5.2
# jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 3 ] || { sed -n '2,6p' "$0"; exit 2; }
kind=$1; base=$2; out=$3
case "$kind" in
    gpm|dipo) srcs="Bar BarOut Near" ;;
    navi) srcs="Bar BarOut NaviBar" ;;
    *) sed -n '2,6p' "$0"; exit 2 ;;
esac
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
files=()
for s in $srcs; do files+=("$here/bar/com/jmk/hud/$s.java"); done
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" "${files[@]}"
(cd "$work/classes" && jar cf "$work/bar.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/bar.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/bar.py" "$kind" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
