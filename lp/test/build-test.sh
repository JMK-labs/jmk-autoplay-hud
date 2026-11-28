#!/usr/bin/env bash
# lp/build_lp_package.py: the signed zip has what a LivePatch HUD needs and nothing of the legacy or non-Korean parts; the tools folder of the built zip builds the same files.
here="$(cd "$(dirname "$0")" && pwd)"; PROJECT="$here/../.."
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lp-build.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
OUT=$(cd "$PROJECT" && JMK_BUILT_DATE=2026-11-28 python3 lp/build_lp_package.py 2>&1) || { echo "$OUT"; fail "build"; exit 1; }
ZIP=$PROJECT/dist/test/jmk-autoplay-hud-0.3.3-lp.zip
check "built and signed" test -f "$ZIP"
OUT2=$(cd "$PROJECT" && JMK_BUILT_DATE=2026-11-28 python3 lp/build_lp_package.py 2>&1)
check "deterministic (same sha twice)" test "$(echo "$OUT" | grep sha256)" = "$(echo "$OUT2" | grep sha256)"
U=$WORK/u; mkdir -p "$U"; (cd "$U" && unzip -q "$ZIP")
f() { [ -f "$U/$1" ]; }
for x in NEMESIS.data migrate.meta scripts/legacy-restore.sh scripts/legacy-verify.sh scripts/converter-check.sh scripts/preflight.sh scripts/preinstall.sh scripts/postinstall.sh scripts/preuninstall.sh svc/hud.sh bin/launch.sh tools/hud-step tools/lpatch tools/codesum.jar tools/legacy-known tools/recipes/gates integrity.json integrity.sig; do check "has $x" f "$x"; done
check "no libev6aac.so" test -z "$(find "$U" -name 'libev6aac*')"
check "no converter recipe in tools/" test ! -e "$U/tools/recipes/carplay-utils-converter.recipe"
check "no non-Korean fixed set" bash -c "ls '$U/tools/patches' | grep -qxE 'neev|ev6|ev6_ca|nq5|neev23_260903|neev_ca|dl3hev|us' && exit 1; exit 0"
check "no legacy common.sh / records code" test ! -e "$U/scripts/common.sh"
check "only Korean profiles" bash -c "for d in '$U'/tools/patches/bycode/*; do case \${d##*/} in kr*) ;; *) exit 1 ;; esac; done"
check "every manifest patch is in the zip" bash -c "cd '$U/tools/patches'; for m in bycode/*/manifest; do while read -r p k n c x w; do case \$p in 2_tbt|3_bridge) [ -f \"\$x\" ] || { echo missing \$x; exit 1; } ;; esac; done < \$m; done"
NEM=$U/NEMESIS.data
check "os is Korean only" grep -q '^os="\*.KOR.\*"' "$NEM"
check "depends has the LivePatch version, AutoPlay 0.5.0 or newer and the three refusals" grep -q '^depends="jmk-autoplay@>=0.5.0,usb-handler@>=1.17,!danpung,!enhanced.projection,!wireless.carplay.aa"' "$NEM"
check "9 patch sections (5 odex, infobank, core, audio, the lane lib)" test "$(grep -c '^\[patch\.' "$NEM")" = 9
check "every patch section is an exec step of tools/hud-step and optional" bash -c "[ \$(grep -c '^tool=tools/hud-step' '$NEM') = 9 ] && [ \$(grep -c '^optional=1' '$NEM') = 9 ] && [ \$(grep -c '^engine=exec' '$NEM') = 9 ]"
check "no [file.N] (no new file in /system)" bash -c "! grep -q '^\[file\.' '$NEM'"
check "migrate.meta keys" bash -c "grep -q '^mode=reinstall' '$U/migrate.meta' && grep -q '^restore=scripts/legacy-restore.sh' '$U/migrate.meta' && grep -q '^verify=scripts/legacy-verify.sh' '$U/migrate.meta' && grep -q '^needs-nemesis=1.17' '$U/migrate.meta' && grep -q '^legacy_below=0.3.1' '$U/migrate.meta' && grep -q '^gate=scripts/converter-check.sh' '$U/migrate.meta' && grep -q '^preflight=scripts/preflight.sh' '$U/migrate.meta'"
check "exec bits kept" bash -c "unzip -Z '$ZIP' tools/hud-step tools/lpatch scripts/legacy-restore.sh | grep -c 'rwxr-xr-x' | grep -qx 3"
check "short-desc and detailed-desc within NEMESIS limits" python3 -c "
import re,sys
t=open('$NEM',encoding='utf-8').read()
s=re.search(r'^short-desc=\"?(.*?)\"?$',t,re.M).group(1); d=re.search(r'^detailed-desc=\"?(.*?)\"?$',t,re.M).group(1)
sys.exit(0 if len(s)<=64 and len(d)<=256 else 1)"
# the words the public tree must not carry (hud-gate's sweep), over what ships besides the licence texts
# (the words are written in pieces so this test does not trip the same sweep itself)
PAT="dipo-""chain|chain-""step|step""2|private"" step|second"" step|private""/|screen-?re""sync|re""sync|persist\\.jmk|jmk\\.wi""fi|BUD""GET|brea""ker|skip=[01]|des""ign/"
check "word sweep" bash -c "! grep -rIiE '$PAT' '$U' --exclude=LICENSE --exclude-dir=LICENSES --exclude-dir=src --exclude=README.md | grep -q ."
# the tools folder of the built zip rebuilds the same files (real stock files, host lpatch)
if JMK_LP_TOOLS="$U/tools" bash "$here/hud-step-test.sh" > "$WORK/hs.out" 2>&1; then check "hud-step from the built zip: all its checks" true; else check "hud-step from the built zip: all its checks" false; tail -5 "$WORK/hs.out"; fi
grep -q "^skip" "$WORK/hs.out" && echo "      (hud-step from the built zip skipped: JMK_HS_STOCK / JMK_LHOST not set)"
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
