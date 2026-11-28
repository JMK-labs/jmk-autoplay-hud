#!/usr/bin/env bash
# lp/package/tools/hud-step on the Mac: real stock files of a Korean Ioniq 5, the host lpatch, a stub dexopt.
# The stub dexopt copies the apk it is given, so the code inside the "odex" can be checked against the profile's result md5.
here="$(cd "$(dirname "$0")" && pwd)"
PAT=$here/../../package/patches RCP=$here/../../package/recipes
# Real stock files of a Korean Ioniq 5 and the host build of lpatch are not part of this tree: JMK_HS_STOCK = a flat folder with HKMC_DiPO.odex HKMC_Navi_ExSL.odex
# Iap2ServerApp.odex HKMC_GPM.odex PhoneProjection.odex HKMC_GPM.apk Iap2ServerApp.apk libautoreceiver_infobank.so libCarPlayCore.so; JMK_LHOST = the host lpatch.
STOCK=${JMK_HS_STOCK:-}; LHOST=${JMK_LHOST:-}
if [ ! -d "$STOCK" ] || [ ! -x "$LHOST" ]; then echo "skip: set JMK_HS_STOCK and JMK_LHOST (tools/jmk-autoplay-hud/hud-lp-tests.sh does)"; exit 0; fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hs-test.XXXXXX"); trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
q() { md5 -q "$1" 2>/dev/null; }
# the package as NEMESIS stages it: tools/ with the tool, lpatch, patches, recipes (no converter recipe), the known list.
# JMK_LP_TOOLS=<dir>: use the tools/ folder of an unpacked built zip instead (build-test.sh), with the host lpatch put over the ARM one.
if [ -n "$JMK_LP_TOOLS" ]; then T=$WORK/pkg/tools; mkdir -p "$WORK/pkg"; cp -R "$JMK_LP_TOOLS" "$T"; cp "$LHOST" "$T/lpatch"; PAT=$T/patches
else
T=$WORK/pkg/tools; mkdir -p "$T/recipes"
cp "$here/../package/tools/hud-step" "$T/"; cp "$here/../package/tools/legacy-known" "$T/"; cp "$LHOST" "$T/lpatch"; cp "$here/../../package/tools/codesum.jar" "$T/"
cp -R "$PAT" "$T/patches"; for f in "$RCP"/*; do case "$f" in */carplay-utils-converter.recipe) ;; *) cp "$f" "$T/recipes/" ;; esac; done
fi
# a fake car root: stock files behind `nemesis livepatch stock`
CAR=$WORK/car; mkdir -p "$CAR/system/app" "$CAR/system/lib" "$CAR/system/xbin" "$CAR/system/bin" "$CAR/system/framework" "$CAR/stock/system/app" "$CAR/stock/system/lib"
S=$CAR/stock/system
for a in HKMC_DiPO HKMC_Navi_ExSL Iap2ServerApp HKMC_GPM PhoneProjection; do cp "$STOCK/$a.odex" "$S/app/"; done
for a in HKMC_GPM Iap2ServerApp; do cp "$STOCK/$a.apk" "$S/app/"; done
for a in HKMC_DiPO HKMC_Navi_ExSL PhoneProjection; do cp "$STOCK/HKMC_GPM.apk" "$S/app/$a.apk"; done   # a zip is all the stub needs
cp "$STOCK/libautoreceiver_infobank.so" "$S/lib/"; cp "$STOCK/libCarPlayCore.so" "$S/lib/"
cat > "$CAR/system/xbin/nemesis" <<'N'
#!/bin/sh
[ "$1 $2" = "livepatch stock" ] || exit 1
[ -f "$CAR$3" ] || [ -f "$CAR/stock$3" ] || exit 2
cp "$CAR/stock$3" "$4" 2>/dev/null || exit 2
N
chmod +x "$CAR/system/xbin/nemesis"
printf '#!/bin/sh\n[ "$1" = --preopt ] && cp "$2" "$3"\n' > "$CAR/system/bin/dexopt"; chmod +x "$CAR/system/bin/dexopt"
CSCLASSES=$WORK/cs-classes; mkdir -p "$CSCLASSES"; javac -d "$CSCLASSES" "$here/../../src/jmkhud/CodeSum.java" || { echo "javac failed"; exit 1; }
export CSCLASSES
cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { [ "$1" = ro.build.product ] && echo "${PRODUCT:-NEEV.KOR.0000.V039.001.260902}"; }
app_process() { [ "$1 $2" = "/system/bin jmkhud.CodeSum" ] || return 1; shift 2; command java -cp "$CSCLASSES" jmkhud.CodeSum "$@"; }
SH
export CAR
step() {   # step <mode> <name> <in> <out>: OUT, RC
    OUT=$(cd "$T" && JMK_HUD_TEST_ROOT=$CAR JMK_LR_SHIMS=$WORK/shims JMK_LPATCH=$T/lpatch CAR=$CAR sh "$T/hud-step" "$@" 2>&1); RC=$?
}
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
want() {   # want <profile> <part> <kind> <name>: the profile's result md5
    local p k n c x w; while read -r p k n c x w; do [ "$p" = "$2" ] && [ "$k" = "$3" ] && [ "$n" = "$4" ] && { echo "$w"; return; }; done < "$PAT/bycode/$1/manifest"
}
dexin() { rm -rf "$WORK/z"; mkdir -p "$WORK/z"; (cd "$WORK/z" && unzip -qo "$1" classes.dex 2>/dev/null); q "$WORK/z/classes.dex"; }

# the odex steps
step odex HKMC_GPM "$S/app/HKMC_GPM.odex" "$WORK/gpm.odex"
check "GPM: exit 0" test $RC = 0; [ $RC = 0 ] || echo "$OUT"
check "GPM: profile chosen (bridge on a seen framework or not, said in the log)" has "choose profile="
echo "      $(echo "$OUT" | grep -m1 'choose profile=')"
P=$(echo "$OUT" | grep -m1 'choose profile=' | { read -r a b c; b=${b#profile=}; echo "$b"; })
check "GPM: code inside the odex = the profile's result" test "$(dexin "$WORK/gpm.odex")" = "$(want "$P" 2_tbt app HKMC_GPM)"
for a in HKMC_Navi_ExSL Iap2ServerApp HKMC_DiPO; do
    step odex "$a" "$S/app/$a.odex" "$WORK/$a.odex"
    check "$a: exit 0" test $RC = 0
    w=$(want "$P" 3_bridge app "$a"); [ -n "$w" ] || w=$(want "$P" 2_tbt app "$a")
    check "$a: code = the profile's result" test "$(dexin "$WORK/$a.odex")" = "$w"
done
# PhoneProjection: bridge only
step odex PhoneProjection "$S/app/PhoneProjection.odex" "$WORK/pp.odex"
case "$OUT" in *"parts=2_tbt 3_bridge"*) check "PhoneProjection: built (bridge profile)" test $RC = 0 ;; *) check "PhoneProjection: pass-through when no bridge (10)" test $RC = 10 ;; esac
# the library step
step lib libautoreceiver_infobank.so "$S/lib/libautoreceiver_infobank.so" "$WORK/ib.so"
check "infobank: exit 0" test $RC = 0
check "infobank: result md5 = the profile's" test "$(q "$WORK/ib.so")" = "$(want "$P" 2_tbt file libautoreceiver_infobank.so)"
# the recipe step: the Korean libCarPlayCore ef49c09b gets the frame-wait recipe, the gate result md5
step recipes libCarPlayCore.so "$S/lib/libCarPlayCore.so" "$WORK/core.so"
check "Core: recipe built (0) or native (10)" test "$RC" = 0 -o "$RC" = 10
echo "      $(echo "$OUT" | tail -1)"
[ $RC = 0 ] && check "Core: result md5 = the gate's" test "$(q "$WORK/core.so")" = 36c65d80ea46f833f84c7567f43ffc2b
step recipes libCarPlayAudio.so "$S/lib/libCarPlayCore.so" "$WORK/aud.so"
check "a library no recipe names: pass-through (10)" test $RC = 10
# the audio-formats recipe on a real stock libCarPlayAudio.so (optional sample: JMK_HS_AUDIO), and its own result as <in>
if [ -n "$JMK_HS_AUDIO" ] && [ -f "$JMK_HS_AUDIO" ]; then
    cp "$JMK_HS_AUDIO" "$S/lib/libCarPlayAudio.so"
    step recipes libCarPlayAudio.so "$S/lib/libCarPlayAudio.so" "$WORK/audio.so"
    check "Audio: stock sample builds with the recipe (0)" test $RC = 0
    check "Audio: result md5 is the recipe's result on that stock" test "$(q "$WORK/audio.so")" = "${JMK_HS_AUDIO_RESULT:-$(q "$WORK/audio.so")}"
    step recipes libCarPlayAudio.so "$WORK/audio.so" "$WORK/audio2.so"
    check "Audio: the recipe's own result as <in> is refused (1), not passed through" test $RC = 1
    check "  reason says restore first" has "restore the stock files first"
    check "  no output" test ! -s "$WORK/audio2.so"
fi
# the lane recipe on the real stock libiap2session.so (optional sample: JMK_HS_IAP2S, md5 fc7cb675…): built, its own result refused, any other md5 passed through with the log line
if [ -n "$JMK_HS_IAP2S" ] && [ -f "$JMK_HS_IAP2S" ]; then
    check "Lanes: the sample is the stock file the recipe is gated on" test "$(q "$JMK_HS_IAP2S")" = fc7cb675b46a44bd893a1edc054c5e71
    step recipes libiap2session.so "$JMK_HS_IAP2S" "$WORK/iap2s.so"
    check "Lanes: stock libiap2session.so builds with the recipe (0)" test $RC = 0
    check "Lanes: result md5 is the gate's" test "$(q "$WORK/iap2s.so")" = 4ce639fea732b1ec052407d0b5548c42
    step recipes libiap2session.so "$WORK/iap2s.so" "$WORK/iap2s2.so"
    check "Lanes: the recipe's own result as <in> is passed through (10), never refused (an exit 1 would fail the whole install)" test $RC = 10
    check "  no output, the line says the lane part stays off" test ! -s "$WORK/iap2s2.so" && has "lanes off"
    cp "$JMK_HS_IAP2S" "$WORK/other.so"; printf 'Z' | dd of="$WORK/other.so" bs=1 seek=4096 conv=notrunc 2>/dev/null
    om=$(q "$WORK/other.so")
    step recipes libiap2session.so "$WORK/other.so" "$WORK/iap2s3.so"
    check "Lanes: another md5 is passed through (10), nothing written" test $RC = 10 -a ! -s "$WORK/iap2s3.so"
    check "  the log line names the first 8 hex digits and says lanes off" has "cp lanes: lib md5 ${om%????????????????????????} not known, lanes off"
    : > "$WORK/empty.so"; echo x > "$WORK/empty.so"
    step recipes libiap2session.so "$WORK/empty.so" "$WORK/iap2s4.so"
    check "Lanes: a file that is no library at all is passed through (10) with the same line" test $RC = 10
fi
# the pins
cp "$WORK/gpm.odex" "$WORK/own.odex"      # an apk-shaped file is not an odex: odexdex fails
step odex HKMC_GPM "$WORK/own.odex" "$WORK/o2.odex"
check "not an odex: pass-through or refused, never built" test "$RC" != 0
check "not built: no output" test ! -s "$WORK/o2.odex"
step odex HKMC_GPM "$S/app/HKMC_Navi_ExSL.odex" "$WORK/o3.odex"
check "another app's odex as GPM's: pass-through (10), never built" test $RC = 10
step lib libautoreceiver_infobank.so "$WORK/ib.so" "$WORK/ib2.so"
check "our own library result as <in>: refused or passed, never rebuilt" test "$RC" != 0
check "  no output" test ! -s "$WORK/ib2.so"
# relative $0 is refused (the tool must not depend on the cwd)
OUT=$(cd "$T" && JMK_HUD_TEST_ROOT=$CAR JMK_LR_SHIMS=$WORK/shims sh ./hud-step odex HKMC_GPM "$S/app/HKMC_GPM.odex" "$WORK/x.odex" 2>&1); RC=$?
check "relative \$0 refused" test $RC = 1
# determinism: the same input gives the same odex
step odex HKMC_GPM "$S/app/HKMC_GPM.odex" "$WORK/gpm2.odex"
check "same input, same output" test "$(q "$WORK/gpm.odex")" = "$(q "$WORK/gpm2.odex")"
# a firmware whose code is in no profile: pass-through, nothing built
cp "$S/app/HKMC_Navi_ExSL.odex" "$WORK/bad.odex"; sz=$(wc -c < "$WORK/bad.odex"); printf 'ZZZZ' | dd of="$WORK/bad.odex" bs=1 seek=$((sz / 2)) conv=notrunc 2>/dev/null
step odex HKMC_Navi_ExSL "$WORK/bad.odex" "$WORK/bad.out"
check "code that is in no profile: never built (pass-through 10)" test "$RC" = 10
check "  no output" test ! -s "$WORK/bad.out"
# preinstall's question: does any HUD odex of this unit carry a code no profile knows? (tools/hud-step unknown)
step unknown
check "unknown: a stock unit has no unknown code (exit 0)" test "$RC" = 0
check "  the answer line" has "unknown=none"
cp "$S/app/HKMC_Navi_ExSL.odex" "$WORK/navi.keep"; cp "$WORK/bad.odex" "$S/app/HKMC_Navi_ExSL.odex"
step unknown
check "unknown: a Navi odex with another code is found (exit 11)" test "$RC" = 11
check "  names the app and the first 8 hex digits of the code" has "app=HKMC_Navi_ExSL code="
check "  the code is not stock and not ours, said in the log" has "code "
echo "      $(echo "$OUT" | tail -1)"
echo 'not an odex' > "$S/app/HKMC_Navi_ExSL.odex"
step unknown
check "unknown: a code that cannot be read is not judged (exit 0)" test "$RC" = 0
cp "$WORK/navi.keep" "$S/app/HKMC_Navi_ExSL.odex"
step unknown
check "unknown: stock again, exit 0" test "$RC" = 0
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
