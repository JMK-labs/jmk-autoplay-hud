#!/usr/bin/env bash
# A DiPO bridge result dex -> the same build with the call-out of callout.py (the classes are com/jmk/hud/Callout.java and the client in
# src/callout/jmkhud/link/):   src/tbt/callout.sh <DiPO bridge result dex> <out dex>
# Steps: javac (Java 7 classes, android-19 on the boot class path) + the Android SDK's d8 (--min-api 19) build the classes; baksmali 2.5.2
# (-a 19) takes both dexes apart; callout.py edits the tree (status 1 when its anchor is not found exactly once); smali 2.5.2 (-a 19,
# one thread: the same input gives the same bytes) puts it back together.
# Needs a JDK, ANDROID_HOME (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, python3, and the smali / baksmali
# 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { sed -n '2,4p' "$0"; exit 2; }
base=$1; out=$2
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" \
    $(find "$here/../callout/jmkhud/link" -name '*.java' | sort) "$here/com/jmk/hud/Callout.java"
(cd "$work/classes" && jar cf "$work/callout.jar" com jmkhud)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/callout.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/callout.py" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
