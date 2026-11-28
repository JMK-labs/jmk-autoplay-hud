#!/usr/bin/env bash
# hud-step profile / the steps when `nemesis livepatch stock` FAILS while our results are mounted (LY3LOBUL 2026-11-28: the settings service read the mounted result as the stock
# and said "locked"). A faked odex (FAKEODEX + the dex text) and a fake profile, no real files needed.
here="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hp-test.XXXXXX"); trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
q() { md5 -q "$1" 2>/dev/null; }
T=$WORK/pkg/tools; mkdir -p "$T/patches/bycode/krx" "$T/recipes"
cp "$here/../package/tools/hud-step" "$T/"; : > "$T/legacy-known"
printf 'STOCKDEX-gpm\n' > "$WORK/s1"; printf 'RESULTDEX-gpm\n' > "$WORK/r1"; printf 'STOCKDEX-dipo\n' > "$WORK/s2"; printf 'RESULTDEX-dipo\n' > "$WORK/r2"
printf '2_tbt app HKMC_GPM %s bycode/krx/a.lpd %s\n2_tbt app HKMC_DiPO %s bycode/krx/b.lpd %s\n' "$(q "$WORK/s1")" "$(q "$WORK/r1")" "$(q "$WORK/s2")" "$(q "$WORK/r2")" > "$T/patches/bycode/krx/manifest"
echo "log" > "$T/patches/bycode/krx/knobs"
printf 'jar' > "$T/codesum.jar"; printf '#!/bin/sh\nexit 1\n' > "$T/lpatch"; chmod +x "$T/lpatch"
cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { echo NEEV.KOR.0000.V039.001.260902; }
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
car() {   # car <name> <stock reader: ok|fail|none> <live gpm: stock|result|other> <live dipo: ...> <mounted: yes|no>
    C=$WORK/car.$1; rm -rf "$C"; mkdir -p "$C/system/app" "$C/system/xbin" "$C/stockfs/system/app"
    printf 'FAKEODEX\nSTOCKDEX-gpm\n' > "$C/stockfs/system/app/HKMC_GPM.odex"; printf 'FAKEODEX\nSTOCKDEX-dipo\n' > "$C/stockfs/system/app/HKMC_DiPO.odex"
    live() { case "$2" in stock) cat "$C/stockfs/system/app/$1.odex" ;; result) printf 'FAKEODEX\nRESULTDEX-%s\n' "$3" ;; other) printf 'FAKEODEX\nUNKNOWN-%s\n' "$3" ;; esac; }
    live HKMC_GPM "$3" gpm > "$C/system/app/HKMC_GPM.odex"; live HKMC_DiPO "$4" dipo > "$C/system/app/HKMC_DiPO.odex"
    MODE_STOCK=$2; MOUNTED=$5
    cat > "$C/system/xbin/nemesis" <<N
#!/bin/sh
case "\$1 \$2" in
  "livepatch status") echo "wrapper=1 safe=0"; if [ "$MOUNTED" = yes ]; then echo "/system/app/HKMC_GPM.odex mounted"; echo "/system/app/HKMC_DiPO.odex mounted"; fi ;;
  "livepatch stock") case "$MODE_STOCK" in ok) cp "$C/stockfs\$3" "\$4" || exit 2 ;; fail) echo "LivePatch cannot read the stock files" >&2; exit 1 ;; none) exit 2 ;; esac ;;
esac
N
    chmod +x "$C/system/xbin/nemesis"
}
prof() { OUT=$(cd "$T" && JMK_HUD_TEST_ROOT=$C JMK_LR_SHIMS=$WORK/shims sh "$T/hud-step" profile 2>&1); RC=$?; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
logged() { grep -q "$1" "$C/data/nemesis/livepatch-jmk-autoplay-hud.log" 2>/dev/null; }

car a ok result result yes; prof
check "stock readable, results mounted: krx via stock (0)" test $RC = 0; check "  via=stock" has "via=stock"; check "  profile krx" has "profile=krx"
car b fail result result yes; prof
check "stock reader FAILS, results mounted (the LY3LOBUL case): profile found from the live results (0)" test $RC = 0
check "  profile krx, only the part it has, via=results" has "profile=krx parts=2_tbt apps=HKMC_GPM,HKMC_DiPO libs= via=results"
check "  the log says the mounted file was not read as stock" logged "not read as stock"
car c fail stock stock no; prof
check "stock reader fails, nothing mounted: the live files are stock, read as such (0)" test $RC = 0; check "  via=stock" has "via=stock"
car d fail other other yes; prof
check "stock reader fails, live code unknown: profile=none (10), saying the stock could not be read" test $RC = 10; check "  says why" has "the stock could not be read"
car e fail result stock yes; prof
check "one app mounted, one stock: still krx via the results (0)" test $RC = 0
car f none stock stock no; prof
check "stock says no such file for everything: none (10)" test $RC = 10
# the build steps must not guess from mounted files either
car g fail result result yes
OUT=$(cd "$T" && JMK_HUD_TEST_ROOT=$C JMK_LR_SHIMS=$WORK/shims sh "$T/hud-step" odex HKMC_GPM "$C/system/app/HKMC_GPM.odex" "$WORK/o.odex" 2>&1); RC=$?
check "odex step with an unreadable stock and mounted results: refused (1), not passed through" test $RC = 1; check "  reason" has "cannot read this unit's stock files"
check "  no output" test ! -s "$WORK/o.odex"
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
