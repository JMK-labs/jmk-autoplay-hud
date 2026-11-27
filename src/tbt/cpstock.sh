#!/usr/bin/env bash
# 0.1.36: a turn-by-turn-only HKMC_DiPO result of 0.1.35 (no com/leafia, no projection) -> the same build whose CarPlay table
# has the stock Korean far-icon numbers again (constants only, cpstock.py):
#   src/tbt/cpstock.sh <0.1.35 result dex> <out dex>
#     6dfde547549483ca65e822f5e992e275, e9b17e59a3231ffdc6b683f312957b10, be272d864b76d0dd0147c1fa64861164,
#     9794821165c1037e0d15f13bb017289d -> see README (0.1.36)
# Steps: baksmali 2.5.2 (-a 19) takes the dex apart; cpstock.py edits eleven constants of com/daudio/app/dipo/e/u.a
# (status 1 when a place is not found exactly once; the bridge builds are refused); smali 2.5.2 (-a 19, one thread: the same
# input gives the same bytes) puts it back together. No class is added. Needs a JDK, python3 and the smali / baksmali
# 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { sed -n '2,6p' "$0"; exit 2; }
base=$1; out=$2
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
python3 -I "$here/cpstock.py" "$work/tree" >&2
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
