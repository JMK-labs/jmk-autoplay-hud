#!/usr/bin/env bash
# 0.1.19: an HKMC_GPM or HKMC_DiPO result dex of 0.1.18 -> the same build with the turn-by-turn clear (tbt-clear.py:
# release at the end of the projection session, the com.jmk.hud.TBT_CLEAR receiver com/jmk/hud/TbtClear.java):
#   src/tbt/clear.sh <0.1.18 result dex> <out dex>
# Every 0.1.19 GPM / DiPO result is this script's output from that profile's 0.1.18 result (README, 0.1.19):
#     GPM   b02ada70f0de90a9e09d364a64559074 -> d2538947dcd6a8af532e0fb2baf7be81   (kr kra krb kre krg kri krp krt, neev_kr)
#           454c8dc4741bf9852e18a6a2ca27be23 -> 965c4bfa035f24caeba188d9450a7e35   (krc krd)
#           1301c92348aab9290e5ee98f4b617cb4 -> 7b0fb9800dc6479d466e06760942ea13   (krm krv)
#     DiPO  56d9ff800ddc5a750fa2be6d247deb5d -> 913848d61d675beb066e03f119a4cf6e   (3_bridge: kr kra krb kre krg kri krp krt, neev_kr)
#           ffe9b558a288cdda39eabd92d4b5fccf -> 6dfde547549483ca65e822f5e992e275   (2_tbt: the same profiles)
#           fe5030232f629489d3249eb7c9ef1c05 -> e9b17e59a3231ffdc6b683f312957b10   (krc)
#           f1c23b5fe21ba6898e1cf9339caf8906 -> be272d864b76d0dd0147c1fa64861164   (krd)
#           29a4add9f184c91b163d9a8b864ce484 -> 9794821165c1037e0d15f13bb017289d   (krm krv)
# Steps: javac (Java 7 classes, the NavigationCluster stub on the class path only) + the Android SDK's d8 (--min-api 19)
# build TbtClear; baksmali 2.5.2 (-a 19) takes both dexes apart; tbt-clear.py edits the tree (stops with status 1 when
# an anchor is not found exactly once); smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it
# back together. Needs a JDK, ANDROID_HOME (or ~/Library/Android/sdk) with platforms/android-19 and build-tools/35.0.0,
# python3, and the smali / baksmali 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
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
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/stub" "$here/stubs/com/hkmc/cluster/NavigationCluster.java"
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -cp "$work/stub" -d "$work/classes" "$here/com/jmk/hud/TbtClear.java"
(cd "$work/stub" && jar cf "$work/stub.jar" com)
(cd "$work/classes" && jar cf "$work/clear.jar" com)
"$d8" --min-api 19 --release --lib "$platform" --classpath "$work/stub.jar" --output "$work" "$work/clear.jar"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$work/classes.dex" -o "$work/tree"
python3 "$here/tbt-clear.py" "$work/tree"
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
