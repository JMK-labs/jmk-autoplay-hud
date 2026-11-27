#!/usr/bin/env bash
# 0.2.2: an HKMC_GPM or HKMC_DiPO bridge result dex -> the same build that logs the lengths of the texts it hands to the cluster
# interface (textlog.py; the class is com/jmk/hud/TextLog.java):   src/tbt/textlog.sh <result dex> <out dex>
# Steps: javac (Java 7 classes, android-19 on the boot class path) + the Android SDK's d8 (--min-api 19) build TextLog; baksmali 2.5.2
# (-a 19) takes both dexes apart; textlog.py edits the tree (status 1 when the places do not have the counts of the build or the edit is
# already there); smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it back together.
# Needs a JDK, ANDROID_HOME (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, python3, and the smali / baksmali
# 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { sed -n '2,3p' "$0"; exit 2; }
base=$1; out=$2
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" "$here/com/jmk/hud/TextLog.java"
(cd "$work/classes" && jar cf "$work/textlog.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/textlog.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/textlog.py" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
