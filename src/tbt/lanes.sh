#!/usr/bin/env bash
# 0.1.29: an HKMC_DiPO bridge result dex of 0.1.22 -> the same build whose CarPlay lane frame carries the lane values of
# com/jmk/hud/Lanes.java (component glyphs for a multi-direction lane; white / blue / grey by the phone's LaneStatus and
# highlight; every lane of the frame logged in Leafia's lane log):
#   src/tbt/lanes.sh <0.1.22 DiPO bridge result dex> <out dex>        d89ed80a6f6757edff7ab29c70b6540a -> see README (0.1.29)
# The input is the 0.1.22 DiPO bridge result (its last step is this directory's apple.sh).
# Steps: javac (Java 7 classes, Lanes against the compile-only LeafiaLane stub) + the Android SDK's d8 (--min-api 19) build
# Lanes; baksmali 2.5.2 (-a 19) takes both dexes apart; lanes.py edits the tree (status 1 when a hook point is not found
# exactly once); smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it back together. Needs a JDK,
# ANDROID_HOME (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, python3, and the smali /
# baksmali 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { sed -n '2,5p' "$0"; exit 2; }
base=$1; out=$2
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/stub" "$here/stubs/com/leafia/kr/LeafiaLane.java"
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -cp "$work/stub" -d "$work/classes" "$here/com/jmk/hud/Lanes.java"
(cd "$work/stub" && jar cf "$work/stub.jar" com)
(cd "$work/classes" && jar cf "$work/lanes.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --classpath "$work/stub.jar" --output "$work" "$work/lanes.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/lanes.py" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
