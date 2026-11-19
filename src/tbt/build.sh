#!/usr/bin/env bash
# 0.1.11: the HKMC_GPM (2_tbt) and HKMC_DiPO (3_bridge) result code of the Korean profiles, from the 0.1.10 result
# code (Leafia KR's build plus the 0.1.5 guidance-end fix), the hooks in near-hooks.diff and com/jmk/hud/Near.java:
#   src/tbt/build.sh <0.1.10 result dex> <out dex>
#     GPM:  990ef4c3cf0f8e828fc8c2de4b327882 -> b02ada70f0de90a9e09d364a64559074
#     DiPO: 86ce5550bedb50e9ce1d07b81b3273a9 -> 1452d2d8c9670bb8f44c39569d3220f5
# Steps: javac (Java 7 classes) + the Android SDK's d8 (--min-api 19) build Near; baksmali 2.5.2 (-a 19) takes both
# dexes apart; near-hooks.diff goes onto com/leafia/kr (LeafiaTurn.standard / reset, LeafiaCpStandard.format /
# routeReset); smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it back together.
# Needs a JDK, ANDROID_HOME (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0, and the
# smali / baksmali 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
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
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" "$here/com/jmk/hud/Near.java"
(cd "$work/classes" && jar cf "$work/near.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/near.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
patch -s -p1 -d "$work/tree" < "$here/near-hooks.diff"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
