#!/usr/bin/env bash
# legacy-restore.sh with NO records at all (the legacy HUD's journal / stock list lost, as on a car whose earlier version wrote files the records do not name):
# every file is judged by what it is, the stock copy comes from the legacy backup / archive directories and is accepted only when our recipe or delta gives the live file.
# Real stock files + the host lpatch (JMK_HS_STOCK, JMK_LHOST, JMK_HS_AUDIO: tools/jmk-autoplay-hud/hud-lp-tests.sh sets them); an odex is faked (the dex is a text line).
here="$(cd "$(dirname "$0")" && pwd)"
SC="$here/../package/scripts"
STOCK=${JMK_HS_STOCK:-}; LHOST=${JMK_LHOST:-}; AUDIO=${JMK_HS_AUDIO:-}
if [ ! -d "$STOCK" ] || [ ! -x "$LHOST" ] || [ ! -f "$AUDIO" ]; then echo "skip: set JMK_HS_STOCK, JMK_LHOST, JMK_HS_AUDIO"; exit 0; fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lrd-test.XXXXXX"); trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
q() { md5 -q "$1" 2>/dev/null; }
PAT=$here/../../package/patches; RCP=$here/../../package/recipes
# the tools folder of the zip: the host lpatch, the Korean profiles, the recipes (no converter), plus one fake profile for the faked odex
TL=$WORK/tools; mkdir -p "$TL/recipes" "$TL/patches/bycode"; cp "$LHOST" "$TL/real-lpatch"
cp -R "$PAT/bycode/kr" "$TL/patches/bycode/kr"; cp -R "$PAT/neev_kr" "$TL/patches/neev_kr"
for f in "$RCP"/*; do case "$f" in */carplay-utils-converter.recipe) ;; *) cp "$f" "$TL/recipes/" ;; esac; done
cp "$here/../package/tools/legacy-known" "$TL/"
printf 'STOCKDEX-of-gpm\n' > "$WORK/stock.dex"; printf 'RESULTDEX-of-gpm\n' > "$WORK/result.dex"
mkdir -p "$TL/patches/bycode/krx"; printf '2_tbt app HKMC_GPM %s bycode/krx/none.lpd %s\n' "$(q "$WORK/stock.dex")" "$(q "$WORK/result.dex")" > "$TL/patches/bycode/krx/manifest"
printf 'jar' > "$TL/codesum.jar"
cp "$TL/real-lpatch" "$TL/lpatch"
cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { case "$1" in ro.build.fingerprint) echo FP1 ;; sys.boot_completed) echo 1 ;; esac; }
pm() { return 0; }
app_process() {   # the code reader on fake odexes: "FAKEODEX" and then the dex text; "extract <odex> <dst>" or the names of several odexes
    [ "$1 $2" = "/system/bin jmkhud.CodeSum" ] || return 1
    shift 2
    local first rest m f n out=
    if [ "$1" = extract ]; then
        { read -r first; read -r rest; } < "$2" || return 0
        if [ "$first" = FAKEODEX ]; then echo "$rest" > "$3"; m=$(command md5 -q "$3"); echo "code=$m"; else echo "code=none"; fi
        return 0
    fi
    for f in "$@"; do
        n=${f##*/}; n=${n%.odex}; first=; rest=; { read -r first; read -r rest; } < "$f"
        if [ "$first" = FAKEODEX ]; then echo "$rest" > "$f.dexcheck"; m=$(command md5 -q "$f.dexcheck"); rm -f "$f.dexcheck"; else m=none; fi
        out="$out$n.code=$m "
    done
    echo "$out"
}
SH
mkdir -p "$WORK/files"; F=$WORK/files
cp "$STOCK/libautoreceiver_infobank.so" "$F/"; cp "$AUDIO" "$F/libCarPlayAudio.so"; cp "$STOCK/libCarPlayCore.so" "$F/"; cp "$STOCK/HKMC_GPM.apk" "$F/"
"$LHOST" apply "$RCP/carplay-audio-formats.recipe" "$F/libCarPlayAudio.so" "$F/audio.patched" >/dev/null
"$LHOST" apply "$RCP/carplay-core-frames-ef49c09b.recipe" "$F/libCarPlayCore.so" "$F/core.patched" >/dev/null
IB_LPD=$(while read -r p k n c x w; do [ "$p" = 2_tbt ] && [ "$k" = file ] && echo "$x"; done < "$PAT/bycode/kr/manifest")
"$LHOST" delta "$PAT/$IB_LPD" "$F/libautoreceiver_infobank.so" "$F/ib.patched" >/dev/null
printf 'x' > "$F/classes.dex"; "$LHOST" zipadd "$F/HKMC_GPM.apk" "$F/classes.dex" "$F/gpm.edited.apk" >/dev/null
printf 'FAKEODEX\nSTOCKDEX-of-gpm\n' > "$F/gpm.stock.odex"; printf 'FAKEODEX\nRESULTDEX-of-gpm\n' > "$F/gpm.result.odex"
car() {   # car <name>: every stock file in place, no record, no backup; $T
    T=$WORK/car.$1; rm -rf "$T"
    mkdir -p "$T/system/app" "$T/system/lib" "$T/system/xbin" "$T/proc" "$T/data/nemesis/backups/jmk-autoplay-hud"
    echo "/dev/block/x /system ext4 rw,relatime 0 0" > "$T/proc/mounts"
    cp "$F/libautoreceiver_infobank.so" "$F/libCarPlayAudio.so" "$F/libCarPlayCore.so" "$T/system/lib/"
    cp "$F/HKMC_GPM.apk" "$T/system/app/"; cp "$F/gpm.stock.odex" "$T/system/app/HKMC_GPM.odex"
}
B() { echo "$T/data/nemesis/backups/jmk-autoplay-hud"; }
A() { echo "$T/data/nemesis/backups/jmk-autoplay-hud.stock"; }
run() { OUT=$(JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims JMK_LR_TOOLS=$TL sh "$SC/legacy-restore.sh" "$@" 2>&1); RC=$?; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
same() { [ "$(q "$1")" = "$(q "$2")" ]; }

car s0; run; check "a stock car, no records: nothing to do (10)" test $RC = 10
run --verify; check "  verify 0" test $RC = 0

# audio patched, the stock copy in the backup dir
car a1; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"; cp "$F/libCarPlayAudio.so" "$(B)/libCarPlayAudio.so"
run --verify; check "audio edited, no record: verify says not stock (1)" test $RC = 1
run; check "  restore exit 0" test $RC = 0; check "  the stock file is back" same "$T/system/lib/libCarPlayAudio.so" "$F/libCarPlayAudio.so"
check "  line says proved by our own data" has "proved by our own data"
run --verify; check "  verify 0 after" test $RC = 0
# the stock copy only in the archive
car a2; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"; mkdir -p "$(A)"; cp "$F/libCarPlayAudio.so" "$(A)/libCarPlayAudio.so.$(q "$F/libCarPlayAudio.so")"
run; check "archive copy only: exit 0" test $RC = 0; check "  stock back" same "$T/system/lib/libCarPlayAudio.so" "$F/libCarPlayAudio.so"
# a wrong copy (another library) in the backup: not accepted
car a3; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"; cp "$F/libCarPlayCore.so" "$(B)/libCarPlayAudio.so"
run; check "wrong copy: exit 1" test $RC = 1; check "  says no copy matches" has "not-stock libCarPlayAudio.so"
check "  nothing written" same "$T/system/lib/libCarPlayAudio.so" "$F/audio.patched"
# no copy anywhere
car a4; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"
run; check "no copy: exit 1" test $RC = 1
# a damaged archive copy (name is the md5 of something else)
car a5; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"; mkdir -p "$(A)"; cp "$F/libCarPlayAudio.so" "$(A)/libCarPlayAudio.so.00000000000000000000000000000000"
run; check "archive copy named by another md5 is skipped: exit 1" test $RC = 1

# core: the frames recipe result
car c1; cp "$F/core.patched" "$T/system/lib/libCarPlayCore.so"; cp "$F/libCarPlayCore.so" "$(B)/libCarPlayCore.so"
run; check "core edited, no record: restored (0)" test $RC = 0; check "  stock back" same "$T/system/lib/libCarPlayCore.so" "$F/libCarPlayCore.so"
# infobank: the profile's delta
car i1; cp "$F/ib.patched" "$T/system/lib/libautoreceiver_infobank.so"; cp "$F/libautoreceiver_infobank.so" "$(B)/libautoreceiver_infobank.so"
run; check "infobank edited, no record: restored (0)" test $RC = 0; check "  stock back" same "$T/system/lib/libautoreceiver_infobank.so" "$F/libautoreceiver_infobank.so"
car i2; cp "$F/ib.patched" "$T/system/lib/libautoreceiver_infobank.so"; cp "$F/libCarPlayAudio.so" "$(B)/libautoreceiver_infobank.so"
run; check "infobank: a copy that does not give the live file: exit 1" test $RC = 1

# apk: a classes.dex entry means edited; a copy with one is not stock
car k1; cp "$F/gpm.edited.apk" "$T/system/app/HKMC_GPM.apk"; cp "$F/HKMC_GPM.apk" "$(B)/HKMC_GPM.apk"
run; check "apk edited, no record: restored (0)" test $RC = 0; check "  stock back" same "$T/system/app/HKMC_GPM.apk" "$F/HKMC_GPM.apk"
car k2; cp "$F/gpm.edited.apk" "$T/system/app/HKMC_GPM.apk"; cp "$F/gpm.edited.apk" "$(B)/HKMC_GPM.apk"
run; check "apk: the only copy is itself edited: exit 1" test $RC = 1

# odex (faked): judged by the code inside, the copy accepted through the same profile line; an archive odex only with this firmware's index line
car o1; cp "$F/gpm.result.odex" "$T/system/app/HKMC_GPM.odex"; cp "$F/gpm.stock.odex" "$(B)/HKMC_GPM.odex"
run; check "odex with a result code, no record: restored (0)" test $RC = 0; check "  stock odex back" same "$T/system/app/HKMC_GPM.odex" "$F/gpm.stock.odex"
car o2; cp "$F/gpm.result.odex" "$T/system/app/HKMC_GPM.odex"; mkdir -p "$(A)"; m=$(q "$F/gpm.stock.odex"); cp "$F/gpm.stock.odex" "$(A)/HKMC_GPM.odex.$m"
run; check "odex: archive copy without this firmware's index line: exit 1" test $RC = 1
echo "HKMC_GPM.odex $m FP1" > "$(A)/index"
run; check "odex: archive copy with the index line: restored (0)" test $RC = 0
printf 'FAKEODEX\nSOMETHING-ELSE\n' > "$T/system/app/HKMC_GPM.odex"
run --verify; check "odex whose code is in no profile: foreign, left alone (verify 0)" test $RC = 0

# a GPM made by HUD 0.2.1 (its own patch, from the repository's history: the result dex b4019f5d is a real 0.2.1 result, not the 0.2.6 one): the records path and the known-list path put stock back
REPO=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO" ] && git -C "$REPO" cat-file -e 8d8dbb5:apps/jmk-autoplay-hud/package/patches/bycode/kr/HKMC_GPM.tbt.lpd 2>/dev/null && [ -f "$STOCK/HKMC_GPM.odex" ]; then
    git -C "$REPO" show 8d8dbb5:apps/jmk-autoplay-hud/package/patches/bycode/kr/HKMC_GPM.tbt.lpd > "$WORK/gpm021.lpd"
    python3 - "$STOCK/HKMC_GPM.odex" "$WORK/gpm.stock.dex" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read(); off, ln = struct.unpack('<II', b[8:16]); open(sys.argv[2], 'wb').write(b[off:off + ln])
PY
    "$LHOST" delta "$WORK/gpm021.lpd" "$WORK/gpm.stock.dex" "$WORK/gpm021.dex" >/dev/null 2>&1
    check "the 0.2.1 patch gives the 0.2.1 result dex (b4019f5d: in the shipped known list, not 0.2.6's 157a712e)" test "$(q "$WORK/gpm021.dex")" = b4019f5da7fd492fe2d83999c984745e
    grep -q "^HKMC_GPM.dex b4019f5da7fd492fe2d83999c984745e$" "$here/../package/tools/legacy-known" && ok "  that md5 is in the shipped known list" || fail "  that md5 is in the shipped known list"
    "$LHOST" zipadd "$F/HKMC_GPM.apk" "$WORK/gpm021.dex" "$WORK/gpm021.apk" >/dev/null 2>&1
    printf 'FAKEODEX\nRESULTDEX-021\n' > "$WORK/gpm021.odex"
    # records path: stock list / applied / made as 0.2.1 wrote them (the format did not change up to 0.2.6), the stock copies in the backup dir
    car r1; cp "$WORK/gpm021.apk" "$T/system/app/HKMC_GPM.apk"; cp "$WORK/gpm021.odex" "$T/system/app/HKMC_GPM.odex"
    cp "$F/HKMC_GPM.apk" "$(B)/HKMC_GPM.apk"; cp "$F/gpm.stock.odex" "$(B)/HKMC_GPM.odex"
    S=$T/data/nemesis/jmk-autoplay-hud; mkdir -p "$S"
    printf 'HKMC_GPM.apk %s\nHKMC_GPM.odex %s\n' "$(q "$F/HKMC_GPM.apk")" "$(q "$F/gpm.stock.odex")" > "$S/stock"
    printf 'HKMC_GPM.apk %s\nHKMC_GPM.odex %s\n' "$(q "$WORK/gpm021.apk")" "$(q "$WORK/gpm021.odex")" > "$S/applied"; cp "$S/applied" "$T/data/nemesis/jmk-autoplay-hud.made"; echo FP1 > "$S/fingerprint"
    run; check "0.2.1-made GPM, records intact: restored (0)" test $RC = 0
    check "  apk is stock again" same "$T/system/app/HKMC_GPM.apk" "$F/HKMC_GPM.apk"
    check "  odex is stock again" same "$T/system/app/HKMC_GPM.odex" "$F/gpm.stock.odex"
    # no records at all: the apk is judged ours by its known 0.2.1 dex and its stock copy is proven, but the odex follows the derive rule, which knows only the CURRENT profile results (the 0.2.1 odex's
    # code is not one of them): no copy can be proved for it, so the restore refuses (1) and writes nothing - the runner stops before any uninstall (the documented lost-records gap)
    car r2; cp "$WORK/gpm021.apk" "$T/system/app/HKMC_GPM.apk"; cp "$WORK/gpm021.odex" "$T/system/app/HKMC_GPM.odex"; cp "$F/HKMC_GPM.apk" "$(B)/HKMC_GPM.apk"; cp "$F/gpm.stock.odex" "$(B)/HKMC_GPM.odex"
    run; check "0.2.1-made GPM, records lost: refused (exit 1)" test $RC = 1
    check "  the odex line is not-stock" has "not-stock HKMC_GPM.odex"
    check "  nothing written: the apk is still the 0.2.1 one" same "$T/system/app/HKMC_GPM.apk" "$WORK/gpm021.apk"
    check "  nothing written: the odex is still the 0.2.1 one" same "$T/system/app/HKMC_GPM.odex" "$WORK/gpm021.odex"
else
    echo "skip  0.2.1-made GPM cases: the repository history (8d8dbb5) or the stock odex is not here"
fi

# the converter library, no record
car v1; cp "$here/../../package/files/libev6aac.so" "$T/system/lib/libev6aac.so"
run; check "converter we shipped, no record: removed (0)" test $RC = 0; check "  gone" test ! -e "$T/system/lib/libev6aac.so"
car v2; echo other > "$T/system/lib/libev6aac.so"; run; check "another libev6aac.so: left alone (10)" test $RC = 10

# several at once, one without a copy: nothing is written
car m1; cp "$F/audio.patched" "$T/system/lib/libCarPlayAudio.so"; cp "$F/core.patched" "$T/system/lib/libCarPlayCore.so"; cp "$F/libCarPlayAudio.so" "$(B)/libCarPlayAudio.so"
run; check "two edited, one copy missing: exit 1" test $RC = 1; check "  the one with a copy is not written either" same "$T/system/lib/libCarPlayAudio.so" "$F/audio.patched"
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
