#!/usr/bin/env bash
# 0.2.2: an HKMC_GPM result dex -> the same build whose Android Auto guidance is not switched off by silence (guide.py):
#   src/tbt/guide.sh <GPM result dex> <out dex>
# Steps: baksmali 2.5.2 (-a 19) takes the dex apart; guide.py edits one place of LeafiaGuide.beat0 (status 1 when it is not found
# exactly once or the edit is already there); smali 2.5.2 (-a 19, one thread: the same input gives the same bytes) puts it back
# together. No class is added. Needs a JDK, python3 and the smali / baksmali 2.5.2 jars (SMALI_JARS, default: the repository's tools/bin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 2 ] || { sed -n '2,3p' "$0"; exit 2; }
base=$1; out=$2
jars=${SMALI_JARS:-$here/../../../../tools/bin}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
java -jar "$jars/baksmali-2.5.2.jar" d -a 19 "$base" -o "$work/tree"
python3 -I "$here/guide.py" "$work/tree" >&2
java -jar "$jars/smali-2.5.2.jar" a -a 19 -j 1 "$work/tree" -o "$out"
md5 -q "$out" 2>/dev/null || md5sum "$out"
