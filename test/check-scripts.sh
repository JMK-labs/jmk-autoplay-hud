#!/usr/bin/env bash
# jmk-autoplay-hud static checks on the Mac:
#  1. syntax of every package script (mksh -n when installed, else bash -n, sh -n and ksh -n);
#  2. nothing the head unit's toolbox/mksh lacks or this car forbids: sed, head, tail, awk, printf, tr, stat, cut,
#     here-documents, fds above 9, and no "remount ro" / sys_ro anywhere;
#  3. the patch data: every set's targets have their patch, stock md5s and the .lpd header's source md5 equal to the
#     stock odex / file; the Korean set against Leafia's own stock and final md5 lists when they are on this Mac;
#  4. the zips: deterministic, licence files inside, nothing obfuscated, never under dist/release;
#  5. no AGPL/GPL code of this package in our closed packages.
here="$(cd "$(dirname "$0")" && pwd)"
P="$here/.."
PKG="$P/package"
REPO="$(cd "$P/../.." && pwd)"
LEAFIA_LC="$REPO/vendor/_dl/leafia-plus-1.0.5/pkg/lifecycle"
n_ok=0; n_fail=0
ok() { echo "ok    $1"; n_ok=$((n_ok + 1)); }
bad() { echo "FAIL  $1"; n_fail=$((n_fail + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
# checks that need inputs this repository does not carry run from a directory given in JMK_HUD_INPUTS (sourced in place); without it they are skipped
hin() { [ -n "${JMK_HUD_INPUTS:-}" ] && [ -f "$JMK_HUD_INPUTS/$1.sh" ] && . "$JMK_HUD_INPUTS/$1.sh"; return 0; }

scripts=$(cd "$PKG" && find . -name '*.sh' | sort)
count=$(echo "$scripts" | grep -c .)
echo "scripts: $count"

# ---------------------------------------------------------------- 1. syntax
if command -v mksh >/dev/null 2>&1; then shells="mksh"; else shells="bash sh ksh"; echo "(mksh not installed: bash -n, sh -n, ksh -n)"; fi
for f in $scripts; do
    for s in $shells; do
        out=$(cd "$PKG" && $s -n "$f" 2>&1)
        check "syntax ($s -n) $f" [ -z "$out" ]
    done
done

# ---------------------------------------------------------------- 2. banned commands (code only: comments and quoted text stripped)
strip() {   # the script with comments, quoted strings and here-doc bodies removed
    python3 -I - "$1" <<'PY'
import re, sys
out = []
for line in open(sys.argv[1], encoding='utf-8'):
    s, q, i, buf = line.rstrip('\n'), None, 0, ''
    while i < len(s):
        c = s[i]
        if q:
            if c == '\\' and q == '"': i += 2; continue
            if c == q: q = None
            i += 1; continue
        if c in '"\'': q = c; i += 1; continue
        if c == '#' and (i == 0 or s[i - 1] in ' \t;|&('): break
        buf += c; i += 1
    out.append(buf)
print('\n'.join(out))
PY
}
for f in $scripts; do
    code=$(strip "$PKG/$f")
    hits=$(echo "$code" | grep -nE '(^|[;&|({`]|\$\(|then|do|else)[[:space:]]*(sed|head|tail|awk|printf|tr|stat|cut|seq|xargs|readlink|basename|dirname)([[:space:]]|$)')
    check "no sed/head/tail/awk/printf/tr/stat/cut in $f" [ -z "$hits" ]
    [ -n "$hits" ] && echo "$hits" | while IFS= read -r h; do echo "      $h"; done
    check "no here-document in $f" eval '! echo "$code" | grep -q "<<"'
    check "no fd above 9 in $f" eval '! echo "$code" | grep -qE "[0-9]{2,}>|>&[0-9]{2,}"'
done
check "no 'remount ro' anywhere in the package" eval '! grep -rq "remount ro" "$PKG" "$P/build_nemesis_package.py"'
check "no sys_ro anywhere in the package" eval '! grep -rq "sys_ro" "$PKG"'
check "remount only ever 'remount rw'" eval '[ -z "$(grep -rhoE "remount [a-z]+" "$PKG/scripts" "$PKG/svc" "$PKG/bin" | grep -v "remount rw")" ]'

# ---------------------------------------------------------------- 3. patch data
lpd_src() { xxd -s 8 -l 16 -p "$1" 2>/dev/null; }
lpd_magic() { [ "$(xxd -l 4 -p "$1" 2>/dev/null)" = 4c504431 ]; }
stock_of() { local f s; while read -r f s; do [ "$f" = "$2" ] && { echo "$s"; return; }; done < "$PKG/patches/$1/stock"; }
effective() {   # the files a set ends with: "part kind name patch md5" (3_bridge replaces 2_tbt, as load_targets)
    local m=$PKG/patches/$1/manifest br
    br=" $(while read -r a b c d e; do [ "$a" = 3_bridge ] && echo "$c"; done < "$m" | tr '\n' ' ') "
    while read -r a b c d e; do
        case "$a" in 2_tbt) case "$br" in *" $c "*) continue ;; esac ;; 3_bridge) ;; *) continue ;; esac
        echo "$a $b $c $d $e"
    done < "$m"
}
sets=$(cd "$PKG/patches" && for d in */; do d=${d%/}; [ -f "$d/manifest" ] && echo "$d"; done)
echo "sets: $(echo $sets)"
for s in $sets; do
    check "set $s: stock and manifest" eval '[ -s "$PKG/patches/$s/stock" ] && [ -s "$PKG/patches/$s/manifest" ]'
    check "set $s: manifest has only 2_tbt / 3_bridge lines" eval '[ -z "$(grep -vE "^(2_tbt|3_bridge) " "$PKG/patches/$s/manifest")" ]'
    while read -r part kind name patch want; do
        lpd="$PKG/patches/$patch"
        check "set $s: $part $name: patch $patch is there and is an lpatch delta" eval '[ -s "$lpd" ] && lpd_magic "$lpd"'
        case "$kind" in app) src=$name.odex; extra=$name.apk ;; *) src=$name; extra= ;; esac
        sum=$(stock_of "$s" "$src")
        check "set $s: $part $name: stock md5 of $src listed" [ -n "$sum" ]
        [ -n "$extra" ] && check "set $s: $part $name: stock md5 of $extra listed" [ -n "$(stock_of "$s" "$extra")" ]
        check "set $s: $part $name: the delta starts from the stock $src ($sum)" [ "$(lpd_src "$lpd")" = "$sum" ]
        check "set $s: $part $name: result md5 well formed" eval '[[ "$want" =~ ^[0-9a-f]{32}$ ]]'
    done < <(effective "$s")
done
# 0.1.4: by-code profiles: every line's delta is there, starts from the line's code (or stock library) md5 and ends at its
# result md5 (the .lpd header holds both), and a part has the apps a set has for it
lpd_dst() { xxd -s 28 -l 16 -p "$1" 2>/dev/null; }
for m in "$PKG"/patches/bycode/*/manifest; do
    prof=${m%/manifest}; prof=${prof##*/}
    check "by code $prof: has 2_tbt lines" grep -q '^2_tbt ' "$m"
    while read -r part kind name code patch want; do
        case "$part" in ''|'#'*|bridge_products|bridge_framework) continue ;; esac   # 0.1.20: the bridge's firmware list is not a part line
        lpd="$PKG/patches/$patch"
        check "by code $prof: $part $name: $patch is an lpatch delta" eval '[ -s "$lpd" ] && lpd_magic "$lpd"'
        check "by code $prof: $part $name: starts from $code" [ "$(lpd_src "$lpd")" = "$code" ]
        check "by code $prof: $part $name: ends at $want" [ "$(lpd_dst "$lpd")" = "$want" ]
        check "by code $prof: $part $name: kind app or file" eval 'case "$kind" in app|file) true ;; *) false ;; esac'
    done < "$m"
done
# krb (2026-11-19): the kr profile's own builds keyed to these cars' code (the same app code, dexopted against a framework
# with one Message / WifiManager method fewer); Navi with this framework's two string IDs. 2026-11-20: the bridge part,
# their PhoneProjection (4e8915b2) being the Tucson's stock code with other ProGuard names: krt's bridge build, and
# DiPO / Iap2 kr's bridge builds
KRB=$PKG/patches/bycode/krb/manifest
want_of() { awk -v p="$2" -v n="$3" '$1==p && $3==n {print $6}' "$1"; }
check "by code krb: a 3_bridge part of three lines (Iap2ServerApp, HKMC_DiPO, PhoneProjection)" [ "$(awk '$1=="3_bridge" {print $3}' "$KRB" | tr '\n' ' ')" = "Iap2ServerApp HKMC_DiPO PhoneProjection " ]
for a in Iap2ServerApp HKMC_DiPO; do
    check "by code krb: $a's bridge line starts from krb's own code (its 2_tbt line's)" [ "$(awk -v n=$a '$1=="3_bridge" && $3==n {print $4}' "$KRB")" = "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4}' "$KRB")" ]
    check "by code krb: $a ends at kr's bridge build" [ "$(want_of "$KRB" 3_bridge $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge $a)" ]
done
check "by code krb: PhoneProjection is group B's code (4e8915b2) -> the same bridge build as Tucson's" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRB")" = "4e8915b28483230964250e3da9463e4e $(want_of "$PKG/patches/bycode/krt/manifest" 3_bridge PhoneProjection)" ]
check "by code krb: the knobs are kr's" cmp -s "$PKG/patches/bycode/krb/knobs" "$PKG/patches/bycode/kr/knobs"
for a in HKMC_GPM HKMC_DiPO Iap2ServerApp; do
    check "by code krb: $a ends at the kr profile's own turn-by-turn build" [ "$(want_of "$KRB" 2_tbt $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
check "by code krb: Navi is kr's build with two framework string IDs changed (another result)" eval '[ -n "$(want_of "$KRB" 2_tbt HKMC_Navi_ExSL)" ] && [ "$(want_of "$KRB" 2_tbt HKMC_Navi_ExSL)" != "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt HKMC_Navi_ExSL)" ]'
check "by code krb: the library line is kr's" [ "$(grep '^2_tbt file ' "$KRB")" = "$(grep '^2_tbt file ' "$PKG/patches/bycode/kr/manifest")" ]
# kra (2026-11-19, K8 / K8 HEV / Seltos): kr's lines, but PhoneProjection keyed to their code with its own bridge build
KRA=$PKG/patches/bycode/kra/manifest
check "by code kra: every line but PhoneProjection is kr's" [ "$(grep -v '^#' "$KRA" | grep -v ' PhoneProjection ')" = "$(grep -v '^#' "$PKG/patches/bycode/kr/manifest" | grep -v ' PhoneProjection ')" ]
check "by code kra: PhoneProjection is K8's code (cd2d9df8) -> its bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRA")" = "cd2d9df8e98bf621e928714bbe4f1723 fb039a6307e3389b71bfdac48de44612" ]
check "by code kra: its PhoneProjection line differs from kr's (another stock code)" [ "$(want_of "$KRA" 3_bridge PhoneProjection)" != "$(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge PhoneProjection)" ]
check "by code kra: the knobs are kr's" cmp -s "$PKG/patches/bycode/kra/knobs" "$PKG/patches/bycode/kr/knobs"
# krt (0.1.7, Tucson NX4 / NX4HEV): kr's lines, PhoneProjection keyed to Tucson's code (1debc2d1) with its bridge build
KRT=$PKG/patches/bycode/krt/manifest
check "by code krt: every line but PhoneProjection is kr's" [ "$(grep -v '^#' "$KRT" | grep -v ' PhoneProjection ')" = "$(grep -v '^#' "$PKG/patches/bycode/kr/manifest" | grep -v ' PhoneProjection ')" ]
check "by code krt: PhoneProjection is Tucson's code -> its bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRT")" = "1debc2d1e4ea8c27b5d3bfd0d9e365d3 255e17ec5425800c19c814a7c6add6a1" ]
check "by code krt: the knobs are kr's" cmp -s "$PKG/patches/bycode/krt/knobs" "$PKG/patches/bycode/kr/knobs"
# krp (0.1.7, Avante CN7PE / CN7NPE): the Ioniq 5's app code with other ProGuard names: every result is kr's build
# (PhoneProjection the same build as Tucson's), keyed to their codes; no library line (their library is another build)
KRP=$PKG/patches/bycode/krp/manifest
for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
    check "by code krp: $a ends at kr's turn-by-turn build" [ "$(want_of "$KRP" 2_tbt $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
for a in Iap2ServerApp HKMC_DiPO; do
    check "by code krp: $a ends at kr's bridge build" [ "$(want_of "$KRP" 3_bridge $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge $a)" ]
done
check "by code krp: PhoneProjection ends at the same bridge build as Tucson's" [ "$(want_of "$KRP" 3_bridge PhoneProjection)" = "$(want_of "$KRT" 3_bridge PhoneProjection)" ]
check "by code krp: no library line" eval '! grep -q "^2_tbt file " "$KRP"'
check "by code krp: the knobs are kr's" cmp -s "$PKG/patches/bycode/krp/knobs" "$PKG/patches/bycode/kr/knobs"
# kre (0.1.7, EV6 Korea CVEV.KOR): the Ioniq 5's app code with other ProGuard names: kr's builds for GPM, DiPO, Navi
# and Iap2, PhoneProjection kr's bridge with android:id/topPanel moved. 0.1.15 (2026-11-20): no library line any more
# (0.1.7-0.1.14 had kr's hook moved to EV6's own library, result 120bab2c: Android Auto dropped with Naver Map on
# DPPB5BHV); its delta left the package
KRE=$PKG/patches/bycode/kre/manifest
for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
    check "by code kre: $a ends at kr's turn-by-turn build" [ "$(want_of "$KRE" 2_tbt $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
for a in Iap2ServerApp HKMC_DiPO; do
    check "by code kre: $a ends at kr's bridge build" [ "$(want_of "$KRE" 3_bridge $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge $a)" ]
done
check "by code kre: PhoneProjection is EV6's code -> its own bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRE")" = "7e61ce5caa6bdc1ad02563fc084e240a 52816a4c37a512da5a118f101ab5f766" ]
check "by code kre (0.1.15): no library line, EV6's library stays stock" eval '! grep -q "^2_tbt file " "$KRE"'
check "by code kre (0.1.15): its library delta is not in the package" [ ! -e "$PKG/patches/bycode/kre/libautoreceiver_infobank.tbt.lpd" ]
check "by code kre (0.1.15): turn-by-turn is still the four apps (GPM, DiPO, Iap2, Navi)" [ "$(awk '$1=="2_tbt" {print $3}' "$KRE" | tr '\n' ' ')" = "HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL " ]
check "by code kre: the knobs are kr's" cmp -s "$PKG/patches/bycode/kre/knobs" "$PKG/patches/bycode/kr/knobs"
# kri (0.1.10, Ioniq 6 Korea CEEV.KOR): krp's app code (CN7 PE's) for GPM, DiPO, Navi; Iap2 the Ioniq 5's; PhoneProjection
# the Ioniq 5's stock code with other ProGuard names and the Ioniq 5's resources: every result is kr's own build
KRI=$PKG/patches/bycode/kri/manifest
check "by code kri: every line but PhoneProjection is krp's" [ "$(grep -v '^#' "$KRI" | grep -v ' PhoneProjection ')" = "$(grep -v '^#' "$KRP" | grep -v ' PhoneProjection ')" ]
check "by code kri: PhoneProjection is CEEV's code (f494a13a) -> kr's own bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRI")" = "f494a13a408aaf5605f86af5a5bb2f95 $(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge PhoneProjection)" ]
check "by code kri: no library line (CN7 PE's library, dbfe7bd2)" eval '! grep -q "^2_tbt file " "$KRI"'
check "by code kri: the knobs are kr's" cmp -s "$PKG/patches/bycode/kri/knobs" "$PKG/patches/bycode/kr/knobs"
# krg (0.1.10, Genesis G70 FL Korea IKFL.KOR): kr's lines, PhoneProjection keyed to its code (637066b5) with its own
# bridge build (kr's with its 8 drawable numbers, not K8's)
KRG=$PKG/patches/bycode/krg/manifest
check "by code krg: every line but PhoneProjection is kr's" [ "$(grep -v '^#' "$KRG" | grep -v ' PhoneProjection ')" = "$(grep -v '^#' "$PKG/patches/bycode/kr/manifest" | grep -v ' PhoneProjection ')" ]
check "by code krg: PhoneProjection is IKFL's code -> its own bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRG")" = "637066b5715c157bd5061452ab6eae2a 027664eba576c42723336759c222de10" ]
for o in kr kra krt krp kre; do
    check "by code krg: its bridge build differs from $o's" [ "$(want_of "$KRG" 3_bridge PhoneProjection)" != "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge PhoneProjection)" ]
done
check "by code krg: the knobs are kr's" cmp -s "$PKG/patches/bycode/krg/knobs" "$PKG/patches/bycode/kr/knobs"
# krv (V037, next release): the Ioniq 5 Korea on the older firmware NEEV.KOR.0000.V037.001.260319, an older source revision
# of the Ioniq 5 KR apps: turn-by-turn only, each app its own result (V037's stock code with kr's turn-by-turn patch
# ported onto it), keyed to V037's codes; the library line is kr's (the same
# library, 48ee793a); no bridge part yet (V037's framework and Broadcom library are needed to check it)
KRV=$PKG/patches/bycode/krv/manifest
check "by code krv: turn-by-turn only, the four apps and the library" [ "$(grep -v '^#' "$KRV" | awk '{print $1":"$3}' | tr '\n' ' ')" = "2_tbt:HKMC_GPM 2_tbt:HKMC_DiPO 2_tbt:Iap2ServerApp 2_tbt:HKMC_Navi_ExSL 2_tbt:libautoreceiver_infobank.so " ]
check "by code krv: no 3_bridge part" eval '! grep -q "^3_bridge " "$KRV"'
for ac in HKMC_GPM:1f29a226774d61a2b4ef899182af28cf:d68ec25745a1f009b462a0ba707fda5d HKMC_DiPO:8d0867878b78347358f136aba85a1287:2c35d0474a684ce64c8de1344d902726 \
          Iap2ServerApp:661dc714e30802d505c333e33bb7f089:cc198983ce4e3c647eda36e23b292143 HKMC_Navi_ExSL:12a34cb11c9325f9a4050a86a9699469:dcdb7bc17374104aaad7ba3316655fe9; do
    a=${ac%%:*}; c=${ac#*:}; w=${c#*:}; c=${c%%:*}
    check "by code krv: $a is V037's code ($c) -> its own build ($w)" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$KRV")" = "$c bycode/krv/$a.tbt.lpd $w" ]
    for o in kr kra krb kre krg kri krk krm krp krt us; do
        check "by code krv: $a's code is no other profile's ($o)" eval '! grep -q " $a $c " "$PKG/patches/bycode/$o/manifest"'
    done
    check "by code krv: $a's build is not kr's (V037's own stock code under the patch)" [ "$w" != "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
check "by code krv: the library line is kr's" [ "$(grep '^2_tbt file ' "$KRV")" = "$(grep '^2_tbt file ' "$PKG/patches/bycode/kr/manifest")" ]
check "by code krv: the knobs are kr's without the Bluetooth key (only the bridge builds read it)" eval '[ "$(grep -v "persist.leafia.cp.keepbt" "$PKG/patches/bycode/kr/knobs" | sed "s/ cp_keepbt//")" = "$(cat "$PKG/patches/bycode/krv/knobs")" ]'
# the profile choice (common.sh bycode_build, sourced as it ships) on the real manifests, for each known car's codes:
# only codesum (the car's helper jar), bycode_make (the build) and md5of (toolbox md5) are replaced
sel_of() {   # sel_of <GPM> <DiPO> <Iap2> <Navi> <PhoneProjection> <library md5>: "<profile> <parts>" or "none"
    local t; t=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-sel.XXXXXX")
    (
        export JMK_HUD_TEST_ROOT=$t; cd "$PKG" || exit 1
        mkdir -p "$t/system/lib" "$t/system/app"
        PKG=$PKG; . "$PKG/scripts/common.sh"; export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        SEL_CODES="HKMC_GPM.code=$1 HKMC_DiPO.code=$2 Iap2ServerApp.code=$3 HKMC_Navi_ExSL.code=$4 PhoneProjection.code=$5"
        echo "$6" > "$t/lib.md5"; echo x > "$LIB_DIR/libautoreceiver_infobank.so"
        for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL PhoneProjection; do echo x > "$APP_DIR/$a.odex"; done
        md5of() { case "$1" in */libautoreceiver_infobank.so) cat "$JMK_HUD_TEST_ROOT/lib.md5" ;; esac; }
        codesum() { echo "$SEL_CODES"; }
        bycode_make() { echo "${1##*/} ${2# }" > "$JMK_HUD_TEST_ROOT/pick"; }
        LOG=$t/log
        bycode_build >/dev/null 2>&1 && cat "$t/pick" || echo none
    )
    rm -rf "$t"
}
KRC="4b4c021c4f58cf5f5aae76e33f9151f5 7abefa3e86fddc50e6cd27e32dc16fb3 30a34f8331e3c74a18c0241a28a036ea 41aa4615841d24e23faf02be05fca29f"
LIB_KR=48ee793af8b86052503b8c952b034731
check "by code choice: an Ioniq 5 Korea V037 car (FI45XFSQ's codes) gets krv, turn-by-turn only" [ "$(sel_of 1f29a226774d61a2b4ef899182af28cf 8d0867878b78347358f136aba85a1287 661dc714e30802d505c333e33bb7f089 12a34cb11c9325f9a4050a86a9699469 3722239dfc58bdc932b23f56bb626c72 $LIB_KR)" = "krv 2_tbt" ]
check "by code choice: V037's code with another library fits nothing (the part is all or nothing)" [ "$(sel_of 1f29a226774d61a2b4ef899182af28cf 8d0867878b78347358f136aba85a1287 661dc714e30802d505c333e33bb7f089 12a34cb11c9325f9a4050a86a9699469 3722239dfc58bdc932b23f56bb626c72 0123456789abcdef0123456789abcdef)" = none ]
check "by code choice: the Ioniq 5 Korea V039 keeps kr with both parts" [ "$(sel_of $KRC d89764a2b7aa475badb9d3c28e3aecc3 $LIB_KR)" = "kr 2_tbt 3_bridge" ]
check "by code choice: K8 / K8 HEV / Seltos keep kra" [ "$(sel_of $KRC cd2d9df8e98bf621e928714bbe4f1723 $LIB_KR)" = "kra 2_tbt 3_bridge" ]
check "by code choice: Tucson keeps krt" [ "$(sel_of $KRC 1debc2d1e4ea8c27b5d3bfd0d9e365d3 $LIB_KR)" = "krt 2_tbt 3_bridge" ]
check "by code choice: G70 FL keeps krg" [ "$(sel_of $KRC 637066b5715c157bd5061452ab6eae2a $LIB_KR)" = "krg 2_tbt 3_bridge" ]
check "by code choice: group B (TMFL, DN8, CN7HEV, LX2) keeps krb" [ "$(sel_of 0f2a3aea66a6eb7ba3c0db5fe65fc684 11e53c789566ac82397e0bed6dda510a ac63fada887e5acc594d96b100238692 6f4fe6b2c6dfb311cdbb2e9f2e2ec5aa 4e8915b28483230964250e3da9463e4e $LIB_KR)" = "krb 2_tbt 3_bridge" ]
check "by code choice: EV6 Korea keeps kre" [ "$(sel_of 9759e803cbff3a612f94fb2302f420a2 e8b7b69bfe0cea6862d2db6ba94ada16 30a34f8331e3c74a18c0241a28a036ea 153eb1b41dd727bf3949a5a27ec59493 7e61ce5caa6bdc1ad02563fc084e240a c4fbccdf63f7d823f24010afec43c937)" = "kre 2_tbt 3_bridge" ]
check "by code choice (0.1.15): EV6 Korea's choice no longer depends on its library (kre has no library line)" [ "$(sel_of 9759e803cbff3a612f94fb2302f420a2 e8b7b69bfe0cea6862d2db6ba94ada16 30a34f8331e3c74a18c0241a28a036ea 153eb1b41dd727bf3949a5a27ec59493 7e61ce5caa6bdc1ad02563fc084e240a 0123456789abcdef0123456789abcdef)" = "kre 2_tbt 3_bridge" ]
check "by code choice: CN7 PE keeps krp, the Ioniq 6 Korea kri" eval '[ "$(sel_of 2487f61fcbae1a779fd92271c7a0360e ce035a13280e222b919d664677928538 30a34f8331e3c74a18c0241a28a036ea bc5ac4a4672362651fb0e523e68f01d3 4ddd81e7e095073156c1130449fdafed dbfe7bd2000000000000000000000000)" = "krp 2_tbt 3_bridge" ] && [ "$(sel_of 2487f61fcbae1a779fd92271c7a0360e ce035a13280e222b919d664677928538 30a34f8331e3c74a18c0241a28a036ea bc5ac4a4672362651fb0e523e68f01d3 f494a13a408aaf5605f86af5a5bb2f95 dbfe7bd2000000000000000000000000)" = "kri 2_tbt 3_bridge" ]'
check "by code choice: US code keeps us" [ "$(sel_of fcd9285700d766d4a75ef9b089dba1e3 77a5160a52ab0f93ab2b14db884b3343 30a34f8331e3c74a18c0241a28a036ea 7dc811232a9171a18c53c337672a4e9c 00000000000000000000000000000000 $LIB_KR)" = "us 2_tbt 3_bridge" ]
# krc / krd (0.1.16): the older firmware .KOR.0000.V035.001.250507, an older source revision than V037's (krv):
# turn-by-turn only, each app the car's own stock code with kr's turn-by-turn patch ported onto it
#; no library line (another build of the library); no bridge part. krc: Carnival KA4
# and Tucson Hybrid NX4HEV (the same code), its Iap2ServerApp V037's code (krv's line); krd: K5 Hybrid DL3HEV (krc's
# code with other names and framework, so its GPM result is krc's and its Iap2ServerApp result krv's)
KRC=$PKG/patches/bycode/krc/manifest; KRD=$PKG/patches/bycode/krd/manifest
for pv in krc:"$KRC" krd:"$KRD"; do
    p=${pv%%:*}; M=${pv#*:}
    check "by code $p: turn-by-turn only, the four apps, no library line" [ "$(grep -v '^#' "$M" | awk '{print $1":"$2":"$3}' | tr '\n' ' ')" = "2_tbt:app:HKMC_GPM 2_tbt:app:HKMC_DiPO 2_tbt:app:Iap2ServerApp 2_tbt:app:HKMC_Navi_ExSL " ]
    check "by code $p: no 3_bridge part" eval '! grep -q "^3_bridge " "$M"'
    check "by code $p: the knobs are kr's without the Bluetooth key (only the bridge builds read it)" eval '[ "$(grep -v "persist.leafia.cp.keepbt" "$PKG/patches/bycode/kr/knobs" | sed "s/ cp_keepbt//")" = "$(cat "$PKG/patches/bycode/$p/knobs")" ]'
done
for ac in krc:HKMC_GPM:4cf385316c37ddc4d5c28ba69d99caee:4a7b32bd43d4771cc4ad902db5563658 krc:HKMC_DiPO:84f17a7a755b5a3022a139526ba452bd:392ad678754574bc66a7a14bd015899b \
          krc:HKMC_Navi_ExSL:ea6e2da50080b288f908962a6c8d5794:3221dcade7641256c63d5d29841cc262 \
          krd:HKMC_GPM:d244aba596a361c850311bb0603d1eab:4a7b32bd43d4771cc4ad902db5563658 krd:HKMC_DiPO:072ba128b4daf9669dc329cfa168a3ee:9cc12db862ce060cee97b946727d7db5 \
          krd:Iap2ServerApp:9f32383bbf425173727ce6365971fa28:cc198983ce4e3c647eda36e23b292143 krd:HKMC_Navi_ExSL:d43adb26a20f55e5bdfd5e313bb66c9d:fcb28613971b8ce110c5e77cd6fb5668; do
    p=${ac%%:*}; r=${ac#*:}; a=${r%%:*}; r=${r#*:}; c=${r%%:*}; w=${r#*:}
    check "by code $p: $a is V035's code ($c) -> its own delta, result $w" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$PKG/patches/bycode/$p/manifest")" = "$c bycode/$p/$a.tbt.lpd $w" ]
    for o in kr kra krb kre krg kri krk krm krp krt krv us krc krd; do
        [ $o = $p ] && continue
        [ $p = krd ] && [ $a = Iap2ServerApp ] && [ $o = krm ] && continue    # krm's Iap2ServerApp is krd's line (checked below)
        check "by code $p: $a's code is no other profile's ($o)" eval '! grep -q " $a $c " "$PKG/patches/bycode/$o/manifest"'
    done
    for o in kr krv; do
        [ $a = Iap2ServerApp ] && [ $o = krv ] && continue    # krd's Iap2ServerApp ends at krv's result (checked below)
        check "by code $p: $a's build is not $o's (V035's own stock code under the patch)" [ "$w" != "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt $a)" ]
    done
done
check "by code krc: Iap2ServerApp is V037's code (661dc714): krv's line, word for word" [ "$(grep '^2_tbt app Iap2ServerApp ' "$KRC")" = "$(grep '^2_tbt app Iap2ServerApp ' "$PKG/patches/bycode/krv/manifest")" ]
check "by code krd: Iap2ServerApp ends at krv's result (V037's code, one other quick slot)" [ "$(want_of "$KRD" 2_tbt Iap2ServerApp)" = "$(want_of "$PKG/patches/bycode/krv/manifest" 2_tbt Iap2ServerApp)" ]
check "by code krd: GPM ends at krc's result (the same code in kr's names)" [ "$(want_of "$KRD" 2_tbt HKMC_GPM)" = "$(want_of "$KRC" 2_tbt HKMC_GPM)" ]
check "by code krc / krd: DiPO and Navi results differ (Navi: two framework string IDs; DiPO: names)" eval '[ "$(want_of "$KRD" 2_tbt HKMC_DiPO)" != "$(want_of "$KRC" 2_tbt HKMC_DiPO)" ] && [ "$(want_of "$KRD" 2_tbt HKMC_Navi_ExSL)" != "$(want_of "$KRC" 2_tbt HKMC_Navi_ExSL)" ]'
LIB_KA4=147dac01e89358ee10c6113e53d7e957; LIB_DL3=ef1e6378e7430d87baed99912be88539
check "by code choice (0.1.16): a Carnival KA4 V035 car (DWWOLTJU's codes) gets krc, turn-by-turn only" [ "$(sel_of 4cf385316c37ddc4d5c28ba69d99caee 84f17a7a755b5a3022a139526ba452bd 661dc714e30802d505c333e33bb7f089 ea6e2da50080b288f908962a6c8d5794 4ba04b34fb542b53a61f4271f3245840 $LIB_KA4)" = "krc 2_tbt" ]
check "by code choice (0.1.16): a Tucson Hybrid NX4HEV V035 car (2DUGUSW2's codes, its own PhoneProjection) gets krc" [ "$(sel_of 4cf385316c37ddc4d5c28ba69d99caee 84f17a7a755b5a3022a139526ba452bd 661dc714e30802d505c333e33bb7f089 ea6e2da50080b288f908962a6c8d5794 edb901264801c09f16dde2c2f088dd0e $LIB_KA4)" = "krc 2_tbt" ]
check "by code choice (0.1.16): a K5 Hybrid DL3HEV V035 car (325RLNAK's codes) gets krd, turn-by-turn only" [ "$(sel_of d244aba596a361c850311bb0603d1eab 072ba128b4daf9669dc329cfa168a3ee 9f32383bbf425173727ce6365971fa28 d43adb26a20f55e5bdfd5e313bb66c9d bf6d2892cc8fa7a12e298836c8f01c08 $LIB_DL3)" = "krd 2_tbt" ]
check "by code choice (0.1.16): V035 code with any library (no library line)" eval '[ "$(sel_of 4cf385316c37ddc4d5c28ba69d99caee 84f17a7a755b5a3022a139526ba452bd 661dc714e30802d505c333e33bb7f089 ea6e2da50080b288f908962a6c8d5794 4ba04b34fb542b53a61f4271f3245840 $LIB_KR)" = "krc 2_tbt" ] && [ "$(sel_of d244aba596a361c850311bb0603d1eab 072ba128b4daf9669dc329cfa168a3ee 9f32383bbf425173727ce6365971fa28 d43adb26a20f55e5bdfd5e313bb66c9d bf6d2892cc8fa7a12e298836c8f01c08 0123456789abcdef0123456789abcdef)" = "krd 2_tbt" ]'
check "by code choice (0.1.16): a Carnival KA4 V037 car (K7UI2BUU's codes) keeps krv" [ "$(sel_of 1f29a226774d61a2b4ef899182af28cf 8d0867878b78347358f136aba85a1287 661dc714e30802d505c333e33bb7f089 12a34cb11c9325f9a4050a86a9699469 f1460f1179fc5050ea2bbebbda36628f $LIB_KR)" = "krv 2_tbt" ]
check "by code choice (0.1.16): V035 with one app of another code fits nothing (the part is all or nothing)" eval '[ "$(sel_of 4cf385316c37ddc4d5c28ba69d99caee 84f17a7a755b5a3022a139526ba452bd 661dc714e30802d505c333e33bb7f089 d43adb26a20f55e5bdfd5e313bb66c9d 4ba04b34fb542b53a61f4271f3245840 $LIB_KA4)" = none ] && [ "$(sel_of d244aba596a361c850311bb0603d1eab 072ba128b4daf9669dc329cfa168a3ee 661dc714e30802d505c333e33bb7f089 d43adb26a20f55e5bdfd5e313bb66c9d bf6d2892cc8fa7a12e298836c8f01c08 $LIB_DL3)" = none ]'
check "by code choice (0.1.16): the LX2 V034 car (KOVZX33T: krd's Iap2ServerApp code, the rest its own) fits nothing" [ "$(sel_of 7117150f01544cfe6491dfc586b39f55 66ef6c36c1b20a894fcfe3283c40202e 9f32383bbf425173727ce6365971fa28 783b9536648a9c96fc79aea3e323e0b8 1be324a2a8113a38a7cfd91cefb01448 0ee6b06b3b9951c6e1eb341df81ed99d)" = none ]
# krm (0.1.18): Kia Sorento MQ4 Korea MQ4.KOR.0000.V037.001.260319 (DWW5FPAD; the Grandeur IGPE V037, OB3JWHQB, has the
# same codes and library): krv's app code (the Ioniq 5 V037's, the same plain code byte for byte) dexopted against a
# framework with group B's core and one Message / UsbDevice / WifiManager method fewer, so only quick slots differ in
# the .odex. GPM and DiPO end at krv's builds, Iap2ServerApp is krd's code (krd's line), Navi is krv's build with that
# framework's two string IDs, the library line kr's; no bridge part
KRM=$PKG/patches/bycode/krm/manifest
check "by code krm: turn-by-turn only, the four apps and the library" [ "$(grep -v '^#' "$KRM" | awk '{print $1":"$3}' | tr '\n' ' ')" = "2_tbt:HKMC_GPM 2_tbt:HKMC_DiPO 2_tbt:Iap2ServerApp 2_tbt:HKMC_Navi_ExSL 2_tbt:libautoreceiver_infobank.so " ]
check "by code krm: no 3_bridge part" eval '! grep -q "^3_bridge " "$KRM"'
for ac in HKMC_GPM:a79f26f3689641f9274c01cdafab52d1:d68ec25745a1f009b462a0ba707fda5d HKMC_DiPO:803a1a0e58d0bc5fed3d0e1fa4ee13bd:2c35d0474a684ce64c8de1344d902726 \
          HKMC_Navi_ExSL:93bca3a2125a1b33c572b20ce6b3a5e1:67a9a0d0b04329e52756233f3ef2042f; do
    a=${ac%%:*}; c=${ac#*:}; w=${c#*:}; c=${c%%:*}
    check "by code krm: $a is MQ4 V037's code ($c) -> its own delta, result $w" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$KRM")" = "$c bycode/krm/$a.tbt.lpd $w" ]
    for o in kr kra krb krc krd kre krg kri krk krp krt krv us; do
        check "by code krm: $a's code is no other profile's ($o)" eval '! grep -q " $a $c " "$PKG/patches/bycode/$o/manifest"'
    done
done
for a in HKMC_GPM HKMC_DiPO; do
    check "by code krm: $a ends at krv's build (the same plain code)" [ "$(want_of "$KRM" 2_tbt $a)" = "$(want_of "$KRV" 2_tbt $a)" ]
done
for o in kr kra krb krc krd kre krg kri krk krp krt krv us; do
    check "by code krm: Navi's build is not $o's (krv's with this framework's two string IDs)" [ "$(want_of "$KRM" 2_tbt HKMC_Navi_ExSL)" != "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_Navi_ExSL)" ]
done
check "by code krm: Iap2ServerApp is krd's code (9f32383b): krd's line, word for word" [ "$(grep '^2_tbt app Iap2ServerApp ' "$KRM")" = "$(grep '^2_tbt app Iap2ServerApp ' "$KRD")" ]
check "by code krm: the library line is kr's (the Ioniq 5's library, 48ee793a)" [ "$(grep '^2_tbt file ' "$KRM")" = "$(grep '^2_tbt file ' "$PKG/patches/bycode/kr/manifest")" ]
check "by code krm: the knobs are kr's without the Bluetooth key (only the bridge builds read it)" eval '[ "$(grep -v "persist.leafia.cp.keepbt" "$PKG/patches/bycode/kr/knobs" | sed "s/ cp_keepbt//")" = "$(cat "$PKG/patches/bycode/krm/knobs")" ]'
MQ4="a79f26f3689641f9274c01cdafab52d1 803a1a0e58d0bc5fed3d0e1fa4ee13bd 9f32383bbf425173727ce6365971fa28 93bca3a2125a1b33c572b20ce6b3a5e1"
check "by code choice (0.1.18): a Sorento MQ4 V037 car (DWW5FPAD's codes) gets krm, turn-by-turn only" [ "$(sel_of $MQ4 8d1a93d8b23ef49abd2ccfeb8449e97f $LIB_KR)" = "krm 2_tbt" ]
check "by code choice (0.1.18): a Grandeur IGPE V037 car (OB3JWHQB's codes, its own PhoneProjection) gets krm" [ "$(sel_of $MQ4 db3b717a98318abff7c7a0119644351d $LIB_KR)" = "krm 2_tbt" ]
check "by code choice (0.1.18): MQ4 V037's code with another library fits nothing (the part is all or nothing)" [ "$(sel_of $MQ4 8d1a93d8b23ef49abd2ccfeb8449e97f 0123456789abcdef0123456789abcdef)" = none ]
check "by code choice (0.1.18): MQ4 V037 with krv's GPM code fits nothing (krv's other codes are not MQ4's)" [ "$(sel_of 1f29a226774d61a2b4ef899182af28cf 803a1a0e58d0bc5fed3d0e1fa4ee13bd 9f32383bbf425173727ce6365971fa28 93bca3a2125a1b33c572b20ce6b3a5e1 8d1a93d8b23ef49abd2ccfeb8449e97f $LIB_KR)" = none ]
# 0.1.17: the dl3hev set (Leafia's original build, unchanged since projection.tbt) is superseded: the by-code profiles
# first. Its cars (DL3, DL322, DL3HEV22, MQ422HEV, MQ4HEV, YGPE, CKPE, DEPEHEV V039.001.260902, all with exactly its stock
# files) run group B's GPM / DiPO / Iap2ServerApp / Navi code (every Leafia dl3hev delta rebuilds its target md5 from it:
# JMK's own tools) and the Ioniq 5's library: krb's turn-by-turn part. Their
# framework-res puts android:id/topPanel at 0x010202f0 (DL3HEV22's upload, as K8's), so their PhoneProjection is not
# group B's 4e8915b2 and krb's bridge part does not fit: held.
DL3_CODES="0f2a3aea66a6eb7ba3c0db5fe65fc684 11e53c789566ac82397e0bed6dda510a ac63fada887e5acc594d96b100238692 6f4fe6b2c6dfb311cdbb2e9f2e2ec5aa"
check "0.1.17 dl3hev: marked superseded (the by-code profiles first)" [ -s "$PKG/patches/dl3hev/superseded" ]
check "0.1.17 dl3hev: the only superseded set" [ "$(ls "$PKG"/patches/*/superseded | wc -l | tr -d ' ')" = 1 ]
check "0.1.17 dl3hev: its stock library is krb's library line (48ee793a)" [ "$(stock_of dl3hev libautoreceiver_infobank.so)" = "$(awk '$1=="2_tbt" && $2=="file" {print $4}' "$KRB")" ]
check "by code choice (0.1.17): the dl3hev set's cars (group B's code, another PhoneProjection) get krb, turn-by-turn only" [ "$(sel_of $DL3_CODES 0123456789abcdef0123456789abcdef $LIB_KR)" = "krb 2_tbt" ]
check "by code choice (0.1.17): ... and with group B's PhoneProjection (4e8915b2) krb with the bridge, as group B" [ "$(sel_of $DL3_CODES 4e8915b28483230964250e3da9463e4e $LIB_KR)" = "krb 2_tbt 3_bridge" ]
check "by code choice (0.1.17): ... with another library nothing (the dl3hev set stays the fallback)" [ "$(sel_of $DL3_CODES 0123456789abcdef0123456789abcdef 0123456789abcdef0123456789abcdef)" = none ]
check "0.1.17 postinstall tries the profiles first for a superseded set" grep -q 'set_superseded "$SET" || ! set_fits "$SET"' "$PKG/scripts/postinstall.sh"
# krk (0.1.20): the bridge for those Kia cars. NLSXQRH5 (Niro Hybrid DEPEHEV V039) sent its PhoneProjection and boot class
# path (DL3HEV22's byte for byte): its PhoneProjection a13280bf is group B's 4e8915b2 raw dump for raw dump but the
# topPanel constant (0x010202ec -> 0x010202f0), and kra's bridge build fb039a63 is krb's 255e17ec with exactly that
# constant changed. Everything else is krb's, word for word.
KRK=$PKG/patches/bycode/krk/manifest
check "by code krk: the bridge only on DEPEHEV / DL3HEV22 V039 (bridge_products)" grep -q '^bridge_products DEPEHEV.KOR.0000.V039.001.260902 DL3HEV22.KOR.0000.V039.001.260902$' "$KRK"
check "by code krk (0.1.28): any car of the framework seen (bridge_framework: framework-res, framework, framework2, automotive)" grep -q '^bridge_framework framework-res.apk=687eeabb4dab7aaf552438c658d5d9a9 framework.odex=eab5af504694910d946f9067310b744a framework2.odex=ad18c214d13478cd1ee877869ac9f00f automotive.odex=3f6c3bf1258723cfa2a6dc75280f19fb$' "$KRK"
check "by code krk (0.1.32): a second framework line (framework-res.apk bae0bd13, the same three odex) opens the bridge for K5 hybrid DL3HEV V039" grep -q '^bridge_framework framework-res.apk=bae0bd131af2e07d9e25f073880b1938 framework.odex=eab5af504694910d946f9067310b744a framework2.odex=ad18c214d13478cd1ee877869ac9f00f automotive.odex=3f6c3bf1258723cfa2a6dc75280f19fb$' "$KRK"
check "by code krk: turn-by-turn and bridge, the lines in krb's order" [ "$(grep -v -e '^#' -e '^bridge_products' -e '^bridge_framework' "$KRK" | awk '{print $1":"$3}' | tr '\n' ' ')" = "$(grep -v '^#' "$KRB" | awk '{print $1":"$3}' | tr '\n' ' ')" ]
check "by code krk: every 2_tbt line is krb's, word for word" [ "$(grep '^2_tbt ' "$KRK")" = "$(grep '^2_tbt ' "$KRB")" ]
for a in Iap2ServerApp HKMC_DiPO; do
    check "by code krk: the $a bridge line is krb's, word for word" [ "$(grep "^3_bridge app $a " "$KRK")" = "$(grep "^3_bridge app $a " "$KRB")" ]
done
check "by code krk: PhoneProjection is DEPEHEV's code (a13280bf) -> its own delta, kra's bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$5" "$6}' "$KRK")" = "a13280bf1adef39877ff6addb5b8ae76 bycode/krk/PhoneProjection.bridge.lpd $(want_of "$PKG/patches/bycode/kra/manifest" 3_bridge PhoneProjection)" ]
for o in kr kra krb krc krd kre krg kri krm krp krt krv us; do
    check "by code krk: its PhoneProjection code is no other profile's ($o)" eval '! grep -q " PhoneProjection a13280bf1adef39877ff6addb5b8ae76 " "$PKG/patches/bycode/$o/manifest"'
done
check "by code krk: only its manifest, the knobs and the PhoneProjection delta (the rest is krb's)" [ "$(ls "$PKG/patches/bycode/krk" | LC_ALL=C sort | tr '\n' ' ')" = "PhoneProjection.bridge.lpd knobs manifest " ]
check "by code krk: the knobs are kr's" cmp -s "$PKG/patches/bycode/krk/knobs" "$PKG/patches/bycode/kr/knobs"
check "by code choice (0.1.20): a Niro Hybrid DEPEHEV V039 car (NLSXQRH5's codes) gets krk with the bridge" [ "$(sel_of $DL3_CODES a13280bf1adef39877ff6addb5b8ae76 $LIB_KR)" = "krk 2_tbt 3_bridge" ]
check "by code choice (0.1.20): ... with another library the bridge part only, as krb with group B's PhoneProjection (no library line in the bridge part)" eval '[ "$(sel_of $DL3_CODES a13280bf1adef39877ff6addb5b8ae76 0123456789abcdef0123456789abcdef)" = "krk 3_bridge" ] && [ "$(sel_of $DL3_CODES 4e8915b28483230964250e3da9463e4e 0123456789abcdef0123456789abcdef)" = "krb 3_bridge" ]'
check "by code choice (0.1.20): group B (4e8915b2) still krb, another PhoneProjection still krb turn-by-turn only" eval '[ "$(sel_of $DL3_CODES 4e8915b28483230964250e3da9463e4e $LIB_KR)" = "krb 2_tbt 3_bridge" ] && [ "$(sel_of $DL3_CODES 0123456789abcdef0123456789abcdef $LIB_KR)" = "krb 2_tbt" ]'
check "by code choice (0.1.20): K8's PhoneProjection (cd2d9df8) with group B's code fits only krb's turn-by-turn (kra's bridge line is keyed to K8's code)" [ "$(sel_of $DL3_CODES cd2d9df8e98bf621e928714bbe4f1723 $LIB_KR)" = "krb 2_tbt" ]
hin 01
hin 02
# 0.1.17 (GMI6OZC2): patches/known, every result an earlier version wrote (src/mkknown.py), for ours()
check "0.1.17 known: src/mkknown.py gives package/patches/known (git history and the zips)" python3 -I "$P/src/mkknown.py" --check
for x in HKMC_GPM.apk:1c4bfddabb210bf4e7dc5e4eefc2c2b0 HKMC_DiPO.apk:33dc9d70b07738af5730e936e3e11c8d HKMC_Navi_ExSL.apk:5115031f79ff6f0b059fcde1a3c1b81d \
         Iap2ServerApp.apk:30c94ea638980401423c56772e778b25 PhoneProjection.apk:677200417207a2e4ff6929550020b459 libautoreceiver_infobank.so:aba7787cb6d365c5ad583a8dc6217ae2; do
    check "0.1.17 known: GMI6OZC2's live ${x%%:*} (${x#*:}, 0.1.0-0.1.4's neev_kr build)" grep -qx "${x%%:*} ${x#*:}" "$PKG/patches/known"
done
known_missing() {   # this version's fixed-set results that patches/known lacks, one per line
    local m set a b c d e
    for m in "$PKG"/patches/*/manifest; do
        set=$(basename "$(dirname "$m")")
        effective "$set" | while read -r a b c d e; do
            [ "$b" = app ] && c=$c.apk
            grep -qx "$c $e" "$PKG/patches/known" || echo "$set $c $e"
        done
    done
}
check "0.1.17 known: every result of this version's fixed sets is in it" [ -z "$(known_missing)" ]
check "0.1.17 known: no stock md5 of any set in it (a stock file is never ours)" eval '! cat "$PKG"/patches/*/stock | grep -v "^#" | while read -r f s; do grep -qx "$f $s" "$PKG/patches/known" && echo "$f"; done | grep -q .'
check "0.1.17 known: no .odex line (our dexopt writes those; ours() follows the apk)" eval '! grep -q "\.odex " "$PKG/patches/known"'
# 0.1.11: the near-turn filter (src/tbt: com.jmk.hud.Near + near-hooks.diff, built by src/tbt/build.sh from the 0.1.10
# results 990ef4c3 / 86ce5550): every Korean profile's GPM and DiPO bridge end at the same two new results, the DiPO
# turn-by-turn build (no near-turn layout in it) is unchanged, and so is the us profile (no Leafia KR code).
# 0.1.13: the DiPO bridge build also carries the wireless iAP2 fix (src/tbt/wireless-iap2.diff, applied by build.sh
# after near-hooks.diff: 86ce5550 -> d760fe5b; 0.1.11's near-turn-only build was 1452d2d8, the GPM build is unchanged).
# 0.1.18: and the CarPlay-channel iAP2 resume (src/tbt/cp-iap-resume.diff, after wireless-iap2.diff: 86ce5550 -> 56d9ff80)
# 0.1.19: GPM and both DiPO builds also carry the turn-by-turn release at the end of the projection session and the
# com.jmk.hud.TBT_CLEAR receiver (src/tbt/tbt-clear.py + TbtClear.java, last in build.sh: GPM 990ef4c3 -> d2538947,
# DiPO 86ce5550 -> 913848d6; src/tbt/clear.sh from each 0.1.18 result gives the same bytes)
# 0.1.22: the DiPO bridge build was d89ed80a (0.1.21: 820be265; 0.1.19 / 0.1.20: 913848d6; neev_kr apk e4cc7bb2 -> ad744980 -> 216af44c)
# 0.1.29: the DiPO bridge build is e1d75f6d (src/tbt/lanes.sh from d89ed80a: the CarPlay lane values); neev_kr apk f0db65c6
NEW_GPM=d2538947dcd6a8af532e0fb2baf7be81; NEW_DIPO=e1d75f6d58f337d8dfe5e32d937225c9; OLD_DIPO=1452d2d8c9670bb8f44c39569d3220f5
DIPO_022=d89ed80a6f6757edff7ab29c70b6540a; DIPO_APK_022=216af44cb16bb542ac0d24844ed6666b
DIPO_013=d760fe5bdb6e00e7afd18fef2155dd1c; NEW_DIPO_APK=f0db65c649bdc3647f2c9da5a569f855; DIPO_019=913848d61d675beb066e03f119a4cf6e
GPM_018=b02ada70f0de90a9e09d364a64559074; DIPO_018=56d9ff800ddc5a750fa2be6d247deb5d; DIPO_APK_018=ad5a3139510fe65a87a0d71f9cd82aff
NEW_DIPOT=6dfde547549483ca65e822f5e992e275; NEW_GPM_APK=00613075311c59881d379f384ed77327; NEW_DIPOT_APK=956eefb7194ab7c3f3294c14a6150d38
# 0.1.34: the final results (turns.sh from 0.1.33's B_ results, which bar.sh makes from the 0.1.32 ones above; both stay the
# intermediate steps of the chain checks below). Navi stays 0.1.33's.
FIN_GPM=157a712e6411f337aa05f62dc9785028; P22_DIPO=c2165b59d16d4b3c3bb2303e0b2920df; T25_CO=68e07332eda0890665e8f046d4c60f8c; T25_TL=3a680d026039df0986ff675e4a1fcdca; P24_DIPO=9f7589c6a36e0ca76c79b368f554d5ad; P25_DIPO=bf4ca0e4cf5e8becff7dc98fbb955539; P26_DIPO=61169fae782dc684f4915a956065a4de; FIN_DIPO=91f91850c21ac076ca8086e2fde798ee; T34_DIPO=7aa7e00904e10e28815e591ef76d0f31   # 0.2.2: textlog.sh (and for GPM guide.sh) on top of the 0.2.1 results
T34_GPM=b4019f5da7fd492fe2d83999c984745e; T21_DIPO=1f999e7152bc9d61044dfaab6974007a   # 0.1.34's GPM (kr family) and 0.2.1's bridge result: the inputs of the 0.2.2 steps
FIN_GPM_APK=c13961a9bdac3c8bfed62956f75682b4; P22_DIPO_APK=1cc900093cf3be3700cc0b5c804121de; P24_DIPO_APK=0588991b38a64a805a76f0e409ede488; P25_DIPO_APK=32036c71adb6d59fc1600090b6cc35b0; FIN_DIPO_APK=5df9d55ecff798c08b04527bdaf837e6; T21_DIPO_APK=abe4c375fa8165086a33e310c0c9ca41; T21_GPM_APK=cd92507988f67c943a73de9626d6772e; T34_DIPO_APK=6706798fbac2d2a0073cd204990aeee2; FIN_NAVI_APK=50ef163c5630bd4adf6afb1e77ab3495
T_GPM=$FIN_GPM; T_DIPO=$FIN_DIPO; T_GPM_C=4a7b32bd43d4771cc4ad902db5563658; T_GPM_M=d68ec25745a1f009b462a0ba707fda5d; T34_GPM_C=2ac1823b45cc72b30353f0e15e800df4; T34_GPM_M=223b8e11c4123e969bb50d792c6851c0
B_GPM=3acf3d096ee019acc1632e83a01feab2; B_DIPO=c9754d6f6dc75d4029ef6c9fdf88389c; B_GPM_C=e7c9a53305a4744327f9184026848d5f; B_GPM_M=8dd363e34a1a34d439b20e5a885700d0
B_NAVI=1a7834c1e814f87db6d92e3fab740003; B_NAVI_B=bc66010be2b488f3326c4bb63d6f5129; B_NAVI_C=3221dcade7641256c63d5d29841cc262
B_NAVI_D=fcb28613971b8ce110c5e77cd6fb5668; B_NAVI_M=67a9a0d0b04329e52756233f3ef2042f; B_NAVI_V=dcdb7bc17374104aaad7ba3316655fe9
B_GPM_APK=4e25776beabcb68f2e48bb5ac3c5857a; B_DIPO_APK=ffbd6a1d915c9c08d3a147d84980cb04; B_NAVI_APK=$FIN_NAVI_APK
# 0.1.36: the turn-by-turn-only DiPO builds (cpstock.sh from the 0.1.19 results: NEW_DIPOT 6dfde547 and the three below; NEW_DIPOT_APK 956eefb7
# for neev_kr). The first is the build of kr kra krb kre krg kri krk krp krt, T36_C of krc, T36_D of krd, T36_M of krm krv.
P22_DIPOT=35711f75785b5cb86cf7c18419b31d29; P22_C=b158cf0486c32f154fdae34e3ff6f9bc; P22_D=11499e9b60afadd852006394ffe58b81; P22_M=f795fd8db6dcd6e301c5d3e815cbd3be; P22_DIPOT_APK=6f8c260d72b44c9d024f1a57d23c1c37
P24_DIPOT=68873db55529d9058afd63a4f24b57a9; P24_C=c085d26ab266804cc3bae47d6763041d; P24_D=eb871121b421e015f455ff6ec3230640; P24_M=ff3d92a2360a4949799e35bdb56be816; P24_DIPOT_APK=95a92e1a711acb859585a6e245f3ca7e
P26_DIPOT=9684024a51b53b3c8363dd9aae4e9388; P26_C=70a507c3a77677fa7f656d5f2326c759; P26_D=a1e991eb8c742ed285d63d2131404265; P26_M=1f5da4289e81e268fee6221084dd4862; P26_DIPOT_APK=3f70c0cd7812d8bf32e1d6cc3eb900f4; P26_DIPO_APK=cb9291834b5279a592beb36b30a8563f   # 0.2.4-0.2.6 results
FIN_DIPOT=3ff67af759ad3304eac6956d345aae7c; T36_C=392ad678754574bc66a7a14bd015899b; T36_D=9cc12db862ce060cee97b946727d7db5; T36_M=2c35d0474a684ce64c8de1344d902726; FIN_DIPOT_APK=94dddca51155c8894fd832fceb38adbf   # 0.3.2: cpend.sh (the new Keep / EndLog / Evt) on top of the 0.2.2 results (P22_*)
C36_F=f121349937ec0b2af47837c2ba6664c8; C36_C=9fecbdac07490655694cd10425b47ffe; C36_D=c202caf20bd19aa890d0a4a28d8d4bdf; C36_M=ba925824f170c4b0a2b4e50dfe02d7e9; C36_APK=134a8a511f8446fef94268a9981c8a64   # cpstock.sh's results: the inputs of 0.2.2's textlog.sh
T19_C=e9b17e59a3231ffdc6b683f312957b10; T19_D=be272d864b76d0dd0147c1fa64861164; T19_M=9794821165c1037e0d15f13bb017289d
for o in kr kra krb kre krg kri krk krp krt; do
    check "0.1.19 $o: GPM ends at the near-turn + TBT clear build $FIN_GPM (0.1.18: $GPM_018)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $FIN_GPM ]
    check "0.1.36 $o: DiPO turn-by-turn build = 0.1.19's $NEW_DIPOT with the stock CarPlay table numbers ($FIN_DIPOT)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_DiPO)" = $FIN_DIPOT ]
    check "0.1.19 $o: DiPO bridge ends at the near-turn + wireless iAP2 + CarPlay-channel resume + TBT clear build $FIN_DIPO (not 0.1.18's $DIPO_018, 0.1.13's $DIPO_013, 0.1.11's $OLD_DIPO)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ]
done
check "0.1.19 neev_kr: GPM delta ends at the near-turn + TBT clear build, DiPO bridge delta at the near-turn + wireless iAP2 + CarPlay-channel resume + TBT clear build" eval '[ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_GPM.tbt.lpd")" = $FIN_GPM ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd")" = $FIN_DIPO ]'
check "0.1.19 neev_kr: result apks (lpatch zipadd of those into the stock apks: GPM $FIN_GPM_APK, DiPO $FIN_DIPO_APK; 0.1.18's 8b13805f / ad5a3139, 0.1.13's DiPO 13633ac6)" eval 'grep -q "^2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd $FIN_GPM_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest"'
check "0.1.11 us: no Leafia KR near-turn code, its results unchanged" eval '[ "$(want_of "$PKG/patches/bycode/us/manifest" 2_tbt HKMC_GPM)" = 6124a666b2ae11883e91de85c19389d2 ] && [ "$(want_of "$PKG/patches/bycode/us/manifest" 3_bridge HKMC_DiPO)" = 5f24681fec4e0ff21f913f3372465524 ]'
# 0.1.13 / 0.1.18: only the Korean DiPO bridge builds change; every other set keeps its DiPO bridge build
for sb in neev:e7c1f412233482e12bde8543c6c1e24f neev23_260903:8b1d23f89ceff4016ade508be1691d18 neev_ca:4150a328e5447ad4511a92cccd49ce10 \
          ev6:154204dd700d02a6d47b4d7b6550c8f6 ev6_ca:83482d5aec90573af95d3bc4e310151f dl3hev:485b12e96b6ff6e88cbfd5cc01de7cd5 nq5:00447fe4ec7b0f6c3cab38c0d7a944bf; do
    check "0.1.13 / 0.1.18 ${sb%%:*}: DiPO bridge build unchanged (${sb#*:})" eval '[ "$(awk '"'"'$1=="3_bridge" && $3=="HKMC_DiPO" {print $5}'"'"' "$PKG/patches/${sb%%:*}/manifest")" = ${sb#*:} ]'
done
for f in src/tbt/com/jmk/hud/Near.java src/tbt/near-hooks.diff src/tbt/build.sh src/tbt/wireless-iap2.diff src/tbt/cp-iap-resume.diff; do
    check "0.1.11 / 0.1.13 / 0.1.18 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
WD=$P/src/tbt/wireless-iap2.diff
check "0.1.13 wireless-iap2.diff: one file (com/daudio/app/dipo/e/b.smali), nothing added" eval '[ "$(grep -c "^+++ " "$WD")" = 1 ] && grep -q "^+++ b/com/daudio/app/dipo/e/b.smali$" "$WD" && [ -z "$(grep "^+" "$WD" | grep -v "^+++ ")" ]'
check "0.1.13 wireless-iap2.diff: takes out exactly the two transport checks (if-eq p1, v0) and their blank lines" eval '[ "$(grep "^-" "$WD" | grep -v "^--- " | grep -c "^-    if-eq p1, v0, :cond_[0-9a-f]*$")" = 2 ] && [ "$(grep "^-" "$WD" | grep -v "^--- " | grep -vc "^-$")" = 2 ] && [ "$(grep -c "^-$" "$WD")" = 2 ]'
check "0.1.13 build.sh: applies wireless-iap2.diff to the DiPO tree only, documents 0.1.13's $DIPO_013 and GPM 990ef4c3 -> $NEW_GPM" eval 'grep -q "if \[ -f \"\$work/tree/com/daudio/app/dipo/e/b.smali\" \]; then" "$P/src/tbt/build.sh" && grep -q "wireless-iap2.diff\"$" "$P/src/tbt/build.sh" && grep -q "0.1.13.s $DIPO_013" "$P/src/tbt/build.sh" && grep -q "990ef4c3cf0f8e828fc8c2de4b327882 -> $NEW_GPM" "$P/src/tbt/build.sh"'
# 0.1.18: the DiPO bridge build also carries the CarPlay-channel iAP2 resume (src/tbt/cp-iap-resume.diff, applied by
# build.sh after wireless-iap2.diff to the tree with Leafia's com/ev6/cpwl/Bridge.smali: 86ce5550 -> 56d9ff80; 0.1.13's
# build was d760fe5b). Only the bridge DiPO changes: the turn-by-turn builds (no Leafia bridge class in them), the
# profiles without a bridge part and every other set keep their results.
CP=$P/src/tbt/cp-iap-resume.diff
check "0.1.18 cp-iap-resume.diff: Leafia's Bridge.smali changed, CpIapResume.smali new, nothing else" eval '[ "$(grep "^+++ " "$CP" | tr "\n" " ")" = "+++ b/com/ev6/cpwl/Bridge.smali +++ b/com/ev6/cpwl/CpIapResume.smali " ] && grep -q "^--- /dev/null$" "$CP"'
check "0.1.18 cp-iap-resume.diff: adds only (no line of Leafia's code taken out)" eval '[ -z "$(grep "^-" "$CP" | grep -v "^--- ")" ]'
check "0.1.18 cp-iap-resume.diff: the hook runs for noti 0 on wireless CarPlay only (if-nez p0, sCpWireless) and posts to Bridge.handler()" \
    eval 'grep -q "^+    if-nez p0, :cond_2b$" "$CP" && grep -q "^+    sget-boolean v1, Lcom/ev6/cpwl/Bridge;->sCpWireless:Z$" "$CP" && grep -q "^+    invoke-static {}, Lcom/ev6/cpwl/Bridge;->handler()Landroid/os/Handler;$" "$CP" && grep -q "^+    invoke-virtual {v1, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z$" "$CP"'
check "0.1.18 cp-iap-resume.diff: the noti stays dropped (the hook goes back to return v0)" eval '[ "$(grep -c "^+    goto :cond_2b$" "$CP")" = 1 ] && grep -q "^     return v0$" "$CP"'
check "0.1.18 cp-iap-resume.diff: CpIapResume.run calls the stock setStartiAP2Service e(1) and nothing else of DiPO's" \
    eval '[ "$(grep "^+    invoke-" "$CP" | grep -c "Lcom/daudio/")" = 1 ] && grep -q "^+    invoke-virtual {v0, v1}, Lcom/daudio/app/dipo/e/b;->e(I)V$" "$CP" && grep -q "^+    const/4 v1, 0x1$" "$CP" && grep -q "^+    sget-object v0, Lcom/daudio/app/dipo/e/u;->leafiaOwner:Lcom/daudio/app/dipo/e/b;$" "$CP"'
check "0.1.18 cp-iap-resume.diff: both new code paths catch Throwable" [ "$(grep -c '^+    \.catch Ljava/lang/Throwable;' "$CP")" = 2 ]
check "0.1.18 build.sh: applies cp-iap-resume.diff after wireless-iap2.diff, to the tree with com/ev6/cpwl/Bridge.smali, documents 86ce5550 -> $DIPO_019" \
    eval 'grep -q "if \[ -f \"\$work/tree/com/ev6/cpwl/Bridge.smali\" \]; then" "$P/src/tbt/build.sh" && [ "$(grep -n "wireless-iap2.diff\"$" "$P/src/tbt/build.sh" | cut -d: -f1)" -lt "$(grep -n "cp-iap-resume.diff\"$" "$P/src/tbt/build.sh" | cut -d: -f1)" ] && grep -q "86ce5550bedb50e9ce1d07b81b3273a9 -> $DIPO_019" "$P/src/tbt/build.sh"'
lpd_extra_has() {   # $1 delta, $2 text: exit 0 when the delta's literal (bsdiff extra) bytes hold the text (a new class
    # name lands there), 1 when they do not, 2 when the delta cannot be read
    python3 -I - "$1" "$2" <<'PY'
import struct, sys, zlib
try:
    d = open(sys.argv[1], 'rb').read()
    assert d[:4] == b'LPD1'
    comp, plen = struct.unpack_from('<II', d, 44)
    assert comp == 1
    b = zlib.decompressobj(-15).decompress(d[52:52 + plen])
    n, = struct.unpack_from('<I', b, 0); q = 4 + 12 * n
    dl, = struct.unpack_from('<I', b, q); q += 4 + dl
    el, = struct.unpack_from('<I', b, q)
    assert q + 4 + el == len(b)
    e = b[q + 4:q + 4 + el]
except Exception:
    sys.exit(2)
sys.exit(0 if sys.argv[2].encode() in e else 1)
PY
}
for lp in bycode/kr bycode/krb bycode/kre bycode/krp neev_kr; do
    check "0.1.18 $lp/HKMC_DiPO.bridge.lpd: ends at $FIN_DIPO and carries the new class (Lcom/ev6/cpwl/CpIapResume;)" eval '[ "$(lpd_dst "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd")" = $FIN_DIPO ] && lpd_extra_has "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd" "Lcom/ev6/cpwl/CpIapResume;"'
done
for lp in "$PKG"/patches/*/HKMC_DiPO.tbt.lpd "$PKG"/patches/bycode/*/HKMC_DiPO.tbt*.lpd "$PKG"/patches/bycode/us/HKMC_DiPO.bridge.*.lpd \
          "$PKG"/patches/neev*/HKMC_DiPO.bridge.lpd "$PKG"/patches/ev6/HKMC_DiPO.bridge.lpd "$PKG"/patches/nq5/HKMC_DiPO.bridge.lpd "$PKG"/patches/dl3hev/HKMC_DiPO.bridge.lpd; do
    [ "$lp" = "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd" ] && continue
    check "0.1.18 ${lp#$PKG/patches/}: no CpIapResume (not a Korean bridge build)" eval 'lpd_extra_has "$lp" "Lcom/ev6/cpwl/CpIapResume;"; [ $? -eq 1 ]'
done
# profiles with no bridge part (their DiPO bridge is held or there is none): no 3_bridge line, turn-by-turn DiPO unchanged
for pd in krc:$T36_C krd:$T36_D krm:$T36_M krv:$T36_M; do
    p=${pd%%:*}; w=${pd#*:}
    check "0.1.18 $p: no 3_bridge part, no DiPO bridge delta (held), its DiPO turn-by-turn build the 0.1.36 one ($w)" eval '! grep -q "^3_bridge " "$PKG/patches/bycode/$p/manifest" && ! ls "$PKG/patches/bycode/$p/" | grep -q "bridge" && [ "$(want_of "$PKG/patches/bycode/$p/manifest" 2_tbt HKMC_DiPO)" = $w ]'
done
check "0.1.36 neev_kr: DiPO turn-by-turn build = 0.1.19's $NEW_DIPOT_APK with the stock CarPlay table numbers ($FIN_DIPOT_APK)" grep -q "^2_tbt app HKMC_DiPO neev_kr/HKMC_DiPO.tbt.lpd $FIN_DIPOT_APK$" "$PKG/patches/neev_kr/manifest"
check "0.1.18 / 0.1.19 known: 0.1.13's and 0.1.18's neev_kr DiPO apks (13633ac6, ad5a3139) and this one ($NEW_DIPO_APK) are all ours" eval 'grep -qx "HKMC_DiPO.apk 13633ac624e850cfad2aa80ddf0be445" "$PKG/patches/known" && grep -qx "HKMC_DiPO.apk $DIPO_APK_018" "$PKG/patches/known" && grep -qx "HKMC_DiPO.apk $NEW_DIPO_APK" "$PKG/patches/known"'
check "0.1.19 known: 0.1.18's neev_kr GPM apk (8b13805f) and this one ($NEW_GPM_APK) are both ours" eval 'grep -qx "HKMC_GPM.apk 8b13805f77cd8bb35691fb8b43a8bb99" "$PKG/patches/known" && grep -qx "HKMC_GPM.apk $NEW_GPM_APK" "$PKG/patches/known"'
hin 03
hin 04
check "0.1.11 near-hooks.diff: the four hooks" [ "$(grep -c '^+.*Lcom/jmk/hud/Near;->' "$P/src/tbt/near-hooks.diff")" = 4 ]
if command -v javac >/dev/null 2>&1; then
    NT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-near.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$NT" "$P/src/tbt/com/jmk/hud/Near.java" "$here/near/com/jmk/hud/NearTest.java" 2>/dev/null; then
        out=$(java -cp "$NT" com.jmk.hud.NearTest 2>&1)
        check "0.1.11 Near on the JVM: $out" [ $? -eq 0 ]
        check "0.1.11 Near on the JVM: every case passed" eval 'case "$out" in "near: all "*) true ;; *) false ;; esac'
    else
        bad "0.1.11 Near.java / NearTest.java compile"
    fi
    rm -rf "$NT"
else
    echo "(no javac: the Near test skipped)"
fi
# 0.1.29: the CarPlay lane values (src/tbt/com/jmk/hud/Lanes.java, ported from HMG-Seogaemo; src/tbt/lanes.py puts three hooks into
# the DiPO bridge tree, src/tbt/lanes.sh: 0.1.22's d89ed80a -> e1d75f6d). Only the Korean DiPO bridge builds change.
for f in src/tbt/com/jmk/hud/Lanes.java src/tbt/lanes.py src/tbt/lanes.sh src/tbt/stubs/com/leafia/kr/LeafiaLane.java; do
    check "0.1.29 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
LJ=$P/src/tbt/com/jmk/hud/Lanes.java
check "0.1.29 Lanes.java: attribution header (hmg-seogaemo, commit fbaacf7, AGPL-3.0, ported, adapted)" eval 'head -6 "$LJ" | grep -q "seogaemo/hmg-seogaemo" && head -6 "$LJ" | grep -q "fbaacf7" && head -6 "$LJ" | grep -q "AGPL-3.0" && head -6 "$LJ" | grep -q "Ported, adapted"'
check "0.1.29 Lanes.java: no Android, no reflection, nothing outside java.util.Arrays and Leafia's lane log" eval '! grep -q "^import android" "$LJ" && ! grep -q "reflect" "$LJ" && [ "$(grep "^import " "$LJ" | tr -d "\n")" = "import java.util.Arrays;" ]'
check "0.1.29 Lanes.java: the one outside call is LeafiaLane.capture (the lane log, tag cp), inside a try" eval '[ "$(grep -c "com\.leafia\.kr\.LeafiaLane\." "$LJ")" = 1 ] && grep -q "com.leafia.kr.LeafiaLane.capture(LOG_TAG, LOG_CALLER" "$LJ" && grep -q "LOG_TAG = \"cp\"" "$LJ"'
LP=$P/src/tbt/lanes.py
check "0.1.29 lanes.py: three hooks (begin, record, patch), all in com/daudio/app/dipo/e/u.smali; nothing else of the build is edited" \
    eval '[ "$(grep -c "Lcom/jmk/hud/Lanes;->" "$LP")" = 3 ] && grep -q "Lcom/jmk/hud/Lanes;->begin()V" "$LP" && grep -q "Lcom/jmk/hud/Lanes;->record(I\[I\[I)V" "$LP" && grep -q "Lcom/jmk/hud/Lanes;->patch(\[B)V" "$LP" && [ "$(grep -c "open(.*, .w.)" "$LP")" = 1 ] && ! grep -q "LeafiaPhoneFrame.smali" "$LP"'
check "0.1.29 lanes.py: stops with status 1 when a hook point is not found exactly once (the profile keeps its build)" eval 'grep -q "found %d times (want 1)" "$LP" && grep -q "already has the Lanes hooks" "$LP"'
check "0.1.29 lanes.py: an empty tree is refused (exit 1, nothing written)" eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-lanes.XXXXXX"); python3 -I "$LP" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.1.29 lanes.sh: the LeafiaLane stub is compile-only (class path, only com/jmk goes into the dex), smali one thread" \
    eval 'grep -q "\-cp \"\$work/stub\"" "$P/src/tbt/lanes.sh" && grep -q "\-\-classpath \"\$work/stub.jar\"" "$P/src/tbt/lanes.sh" && grep -q "lanes.jar" "$P/src/tbt/lanes.sh" && grep -q "smali-2.5.2.jar\" a -a 19 -j 1" "$P/src/tbt/lanes.sh" && grep -q "d89ed80a6f6757edff7ab29c70b6540a" "$P/src/tbt/lanes.sh"'
if command -v javac >/dev/null 2>&1; then
    LT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-lanes.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$LT" "$LJ" "$here/lanes/com/jmk/hud/LanesTest.java" "$here/lanes/com/leafia/kr/LeafiaLane.java" 2>/dev/null; then
        out=$(java -cp "$LT" com.jmk.hud.LanesTest 2>&1)
        check "0.1.29 Lanes on the JVM: $out" [ $? -eq 0 ]
        check "0.1.29 Lanes on the JVM: every case passed" eval 'case "$out" in "lanes: all "*) true ;; *) false ;; esac'
    else
        bad "0.1.29 Lanes.java / LanesTest.java compile"
    fi
    rm -rf "$LT"
else
    echo "(no javac: the Lanes test skipped)"
fi
for lp in bycode/kr bycode/krb bycode/kre bycode/krp neev_kr; do
    check "0.1.29 $lp/HKMC_DiPO.bridge.lpd: ends at $FIN_DIPO and carries the new class (Lcom/jmk/hud/Lanes;)" eval '[ "$(lpd_dst "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd")" = $FIN_DIPO ] && lpd_extra_has "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd" "Lcom/jmk/hud/Lanes;"'
done
for lp in "$PKG"/patches/*/HKMC_DiPO.tbt.lpd "$PKG"/patches/bycode/*/HKMC_DiPO.tbt*.lpd "$PKG"/patches/bycode/us/HKMC_DiPO.bridge.*.lpd \
          "$PKG"/patches/neev*/HKMC_DiPO.bridge.lpd "$PKG"/patches/ev6/HKMC_DiPO.bridge.lpd "$PKG"/patches/nq5/HKMC_DiPO.bridge.lpd "$PKG"/patches/dl3hev/HKMC_DiPO.bridge.lpd; do
    [ "$lp" = "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd" ] && continue
    check "0.1.29 ${lp#$PKG/patches/}: no Lanes class (not a Korean bridge build)" eval 'lpd_extra_has "$lp" "Lcom/jmk/hud/Lanes;"; [ $? -eq 1 ]'
done
check "0.1.29 known: 0.1.22's neev_kr DiPO apk ($DIPO_APK_022) and dex ($DIPO_022) stay ours next to this build" eval 'grep -qx "HKMC_DiPO.apk $DIPO_APK_022" "$PKG/patches/known" && grep -qx "HKMC_DiPO.dex $DIPO_022" "$PKG/patches/known" && grep -qx "HKMC_DiPO.dex $NEW_DIPO" "$PKG/patches/known"'
hin 05
hin 06
# 0.1.33: the cluster near-turn distance bar from the phone's guidance. bar.sh (bar.py hooks, exactly once each) turns every Korean
# GPM, DiPO bridge and Navi result of 0.1.32 into the 0.1.33 one: the window of LeafiaStandard is Near.window() (the stock D: 350 m,
# 1050 m for an expressway turn), the phone processes broadcast the bar (BarOut), the navigation process puts it into its trap-info
# frames (NaviBar). The turn-by-turn-only DiPO builds, the other fixed sets and the us profile are unchanged.
for f in src/tbt/bar/com/jmk/hud/Near.java src/tbt/bar/com/jmk/hud/Bar.java src/tbt/bar/com/jmk/hud/BarOut.java src/tbt/bar/com/jmk/hud/NaviBar.java src/tbt/bar.py src/tbt/bar.sh; do
    check "0.1.33 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
BD=$P/src/tbt/bar/com/jmk/hud
for f in Bar BarOut NaviBar Near; do
    check "0.1.33 $f.java: attribution header (an AGPL-3.0 Korean-firmware mod code base, ported, adapted)" \
        eval 'head -40 "$BD/$f.java" | grep -q "AGPL-3.0 Korean-firmware mod code base" && head -40 "$BD/$f.java" | grep -q "AGPL-3.0" && head -40 "$BD/$f.java" | grep -qi "adapted"'
done
check "0.1.33 Bar.java: no Android (the decisions run on the JVM)" eval '! grep -q "^import android" "$BD/Bar.java" && ! grep -q "^import android" "$BD/Near.java"'
check "0.1.33 the broadcast is our own (com.jmk.hud.BAR, int extra bar, value only), FLAG_RECEIVER_FOREGROUND, sent in a try" \
    eval 'grep -q "ACTION = \"com.jmk.hud.BAR\"" "$BD/Bar.java" && grep -q "EXTRA_BAR = \"bar\"" "$BD/Bar.java" && grep -q "FLAG_RECEIVER_FOREGROUND" "$BD/BarOut.java" && ! grep -rq "^import hmgapi" "$BD"'
check "0.1.33 Near.java (bar): the 0.1.11 entry points the near-hooks.diff calls are all there, D is 350 / 1050, window() is public" \
    eval 'grep -q "public static synchronized int aa(int event, int side, int meters)" "$BD/Near.java" && grep -q "public static synchronized void aaForget()" "$BD/Near.java" && grep -q "public static synchronized int cp(Object c, int\[\] facts, int meters)" "$BD/Near.java" && grep -q "public static synchronized void cpForget(Object c)" "$BD/Near.java" && grep -q "D_GENERAL = 350, D_EXPRESSWAY = 1050" "$BD/Near.java" && grep -q "public static int window()" "$BD/Near.java"'
BP=$P/src/tbt/bar.py
check "0.1.33 bar.py: the hooks are BarOut aa / cp / end and NaviBar info / trap17 / after, and Near.window() in LeafiaStandard" \
    eval 'grep -q "BO = .Lcom/jmk/hud/BarOut;." "$BP" && grep -q "NB = .Lcom/jmk/hud/NaviBar;." "$BP" && grep -q -- "->aa(\[I)V" "$BP" && grep -q -- "->cp(II)V" "$BP" && grep -q -- "->end()V" "$BP" && grep -q -- "->info(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" "$BP" && grep -q -- "->trap17(Ljava/lang/Object;IIIIIIIIIIIIIIIII)I" "$BP" && grep -q -- "->after()V" "$BP" && grep -q "Lcom/jmk/hud/Near;->window()I" "$BP"'
check "0.1.33 bar.py: stops with status 1 when a hook point is not found exactly once (the profile keeps its build)" eval 'grep -q "found %d times (want 1)" "$BP" && grep -q "already has the Bar hooks" "$BP" && grep -q "(n_new, n_int, n_skip) != (3, 1, 1)" "$BP"'
check "0.1.33 bar.py: the wake-up clear frame of NaviSpecialReceiver is left alone" eval 'grep -q "message/dynamic/NaviSpecialReceiver.smali" "$BP"'
for k in gpm dipo navi; do
    check "0.1.33 bar.py $k: an empty tree is refused (exit 1, nothing written)" eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-bar.XXXXXX"); python3 -I "$BP" '$k' "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
done
check "0.1.33 bar.sh: javac + d8 build only our classes (no stub), smali one thread, gpm / dipo carry Near, navi carries NaviBar" \
    eval 'grep -q "smali-2.5.2.jar\" a -a 19 -j 1" "$P/src/tbt/bar.sh" && grep -q "gpm|dipo) srcs=\"Bar BarOut Near\"" "$P/src/tbt/bar.sh" && grep -q "navi) srcs=\"Bar BarOut NaviBar\"" "$P/src/tbt/bar.sh" && grep -q "d2538947dcd6a8af532e0fb2baf7be81" "$P/src/tbt/bar.sh" && grep -q "e1d75f6d58f337d8dfe5e32d937225c9" "$P/src/tbt/bar.sh"'
if command -v javac >/dev/null 2>&1; then
    BJ=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-bar.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$BJ" "$BD/Bar.java" "$BD/Near.java" "$here/bar/com/jmk/hud/BarTest.java" 2>/dev/null; then
        out=$(java -cp "$BJ" com.jmk.hud.BarTest 2>&1)
        check "0.1.33 Bar + Near (D) on the JVM: $out" [ $? -eq 0 ]
        check "0.1.33 Bar + Near (D) on the JVM: every case passed" eval 'case "$out" in "bar: all "*) true ;; *) false ;; esac'
    else
        bad "0.1.33 Bar.java / Near.java / BarTest.java compile"
    fi
    rm -rf "$BJ"
else
    echo "(no javac: the Bar test skipped)"
fi
for pr in kr:$T_GPM:$B_NAVI kra:$T_GPM:$B_NAVI krg:$T_GPM:$B_NAVI krt:$T_GPM:$B_NAVI kre:$T_GPM:$B_NAVI krp:$T_GPM:$B_NAVI kri:$T_GPM:$B_NAVI \
          krb:$T_GPM:$B_NAVI_B krk:$T_GPM:$B_NAVI_B krc:$T_GPM_C:$B_NAVI_C krd:$T_GPM_C:$B_NAVI_D krm:$T_GPM_M:$B_NAVI_M krv:$T_GPM_M:$B_NAVI_V; do
    o=${pr%%:*}; r=${pr#*:}; gv=${r%%:*}; nv=${r#*:}
    check "0.1.33 $o: GPM ends at $gv (the bar build with 0.1.34's turn pictures), Navi at $nv (the bar build)" eval '[ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $gv ] && [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_Navi_ExSL)" = $nv ]'
    for a in HKMC_GPM HKMC_Navi_ExSL; do
        lp=$(awk -v n=$a '$1=="2_tbt" && $3==n {print $5}' "$PKG/patches/bycode/$o/manifest")
        case $a in HKMC_GPM) cls=Lcom/jmk/hud/BarOut\; ;; *) cls=JMKBar ;; esac
        check "0.1.33 $o: $lp ends at the manifest's md5 and carries $cls (its new class)" eval '[ "$(lpd_dst "$PKG/patches/$lp")" = "$(want_of "$PKG/patches/bycode/'$o'/manifest" 2_tbt '$a')" ] && lpd_extra_has "$PKG/patches/$lp" "'$cls'"'
    done
done
for o in kr kra krg krt kre krp kri krb krk; do
    check "0.1.33 $o: DiPO bridge ends at $T_DIPO (the bar build $B_DIPO with 0.1.34's turn pictures)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $T_DIPO ]
done
for lp in bycode/kr bycode/krb bycode/kre bycode/krp neev_kr; do
    check "0.1.33 $lp/HKMC_DiPO.bridge.lpd: ends at $T_DIPO and carries Lcom/jmk/hud/BarOut; (and Bar)" eval '[ "$(lpd_dst "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd")" = $T_DIPO ] && lpd_extra_has "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd" "Lcom/jmk/hud/BarOut;" && lpd_extra_has "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd" "Lcom/jmk/hud/Bar;"'
done
check "0.1.33 neev_kr: GPM delta ends at $T_GPM, Navi delta at $B_NAVI, DiPO bridge delta at $T_DIPO (GPM and DiPO: the bar builds with 0.1.34's turn pictures)" eval '[ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_GPM.tbt.lpd")" = $T_GPM ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_Navi_ExSL.tbt.lpd")" = $B_NAVI ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd")" = $T_DIPO ]'
check "0.1.33 neev_kr: result apks (lpatch zipadd into the stock apks: GPM $FIN_GPM_APK, Navi $B_NAVI_APK, DiPO $FIN_DIPO_APK; 0.1.33's GPM $B_GPM_APK / DiPO $B_DIPO_APK, 0.1.32's 00613075 / 5115031f / f0db65c6)" \
    eval 'grep -q "^2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd $FIN_GPM_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^2_tbt app HKMC_Navi_ExSL neev_kr/HKMC_Navi_ExSL.tbt.lpd $B_NAVI_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest"'
check "0.1.33 the turn-by-turn-only DiPO builds, the other fixed sets and us carry no bar class" \
    eval 'for lp in "$PKG"/patches/*/HKMC_DiPO.tbt.lpd "$PKG"/patches/bycode/*/HKMC_DiPO.tbt*.lpd "$PKG"/patches/bycode/us/*.lpd "$PKG"/patches/neev/*.lpd "$PKG"/patches/neev23_260903/*.lpd "$PKG"/patches/neev_ca/*.lpd "$PKG"/patches/ev6/*.lpd "$PKG"/patches/dl3hev/*.lpd "$PKG"/patches/nq5/*.lpd; do lpd_extra_has "$lp" "Lcom/jmk/hud/BarOut;"; [ $? -eq 1 ] || exit 1; lpd_extra_has "$lp" "JMKBar"; [ $? -eq 1 ] || exit 1; done'
check "0.1.33 known: 0.1.32's results stay ours next to the new ones (GPM d2538947 / $B_GPM, Navi 77980719 / $B_NAVI, DiPO e1d75f6d / $B_DIPO, neev_kr apks 00613075 / f0db65c6 / 5115031f and the new three)" \
    eval 'for kv in HKMC_GPM.dex:d2538947dcd6a8af532e0fb2baf7be81 HKMC_GPM.dex:$B_GPM HKMC_GPM.dex:$B_GPM_C HKMC_GPM.dex:$B_GPM_M HKMC_Navi_ExSL.dex:77980719134a05eea6d784b2113e651f HKMC_Navi_ExSL.dex:$B_NAVI HKMC_Navi_ExSL.dex:$B_NAVI_B HKMC_Navi_ExSL.dex:$B_NAVI_C HKMC_Navi_ExSL.dex:$B_NAVI_D HKMC_Navi_ExSL.dex:$B_NAVI_M HKMC_Navi_ExSL.dex:$B_NAVI_V HKMC_DiPO.dex:$NEW_DIPO HKMC_DiPO.dex:$B_DIPO HKMC_GPM.apk:$NEW_GPM_APK HKMC_GPM.apk:$B_GPM_APK HKMC_Navi_ExSL.apk:5115031f79ff6f0b059fcde1a3c1b81d HKMC_Navi_ExSL.apk:$B_NAVI_APK HKMC_DiPO.apk:$NEW_DIPO_APK HKMC_DiPO.apk:$B_DIPO_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done'
hin 07
hin 08
hin 09
# 0.1.34: the turn pictures (far icon and near layout) as the stock Korean navigation draws them. turns.sh (turns.py hooks, exactly once
# each) turns every Korean GPM and DiPO bridge result of 0.1.33 into the 0.1.34 one; com/jmk/hud/Turns.java decides (JVM test: every
# mapping row before / after), TurnsOut.java is the hooks' side. Navi, the turn-by-turn-only DiPO builds and the other sets stay.
TD=$P/src/tbt/turns/com/jmk/hud; TP=$P/src/tbt/turns.py
for f in src/tbt/turns/com/jmk/hud/Turns.java src/tbt/turns/com/jmk/hud/TurnsOut.java src/tbt/turns.py src/tbt/turns.sh; do
    check "0.1.34 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
for f in Turns TurnsOut; do
    check "0.1.34 $f.java: attribution header (an AGPL-3.0 Korean-firmware mod code base, ported, adapted)" \
        eval 'grep -q "AGPL-3.0 Korean-firmware mod code base" "$TD/$f.java" && grep -q "AGPL-3.0" "$TD/$f.java" && grep -qi "ported, adapted" "$TD/$f.java"'
done
check "0.1.34 Turns.java: no Android, no reflection, no HMG-API (the decisions run on the JVM); TurnsOut catches every Throwable" \
    eval '! grep -q "^import" "$TD/Turns.java" && ! grep -rq "^import hmgapi" "$TD" && [ "$(grep -c "catch (Throwable t)" "$TD/TurnsOut.java")" -ge 7 ]'
check "0.1.34 the log: tag JMKHUD, \"Turn: \" lines for aa and cp with the phone numbers, the far icon and the near layout with their rules; no road or instruction text" \
    eval 'grep -q "TAG = \"JMKHUD\"" "$TD/TurnsOut.java" && grep -q "Log.i(TAG, \"Turn: \" + s)" "$TD/TurnsOut.java" && grep -q "\"aa ev \" + event + \" side \" + side + \" angle \" + angle + \" -> far \"" "$TD/Turns.java" && grep -q "\"type \" + facts\[0\] + \" side \" + facts\[1\] + \" junction \" + facts\[2\] + \" exit \"" "$TD/Turns.java" && ! grep -qi "getName\|roadName\|instruction(" "$TD/TurnsOut.java"'
check "0.1.34 turns.py: the hooks are TurnsOut aaFar / aaNear / aaDir / aaIn / aaOut and cpFar / cpNear / cpSent" \
    eval 'for h in "aaFar(III)I" "aaNear(IIIII)\[I" "aaDir(\[IF)F" "aaIn(II)V" "aaOut(IIIF)V" "cpFar(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;II)I" "cpNear(\[I\[I)\[I" "cpSent(IIF)V"; do grep -q -- "->$h" "$TP" || exit 1; done'
check "0.1.34 turns.py: stops with status 1 when a hook point is not found exactly once or the hooks are there already (the profile keeps its build)" \
    eval 'grep -q "found %d times (want 1)" "$TP" && grep -q "already has the Turns hooks" "$TP" && grep -q "not a 0.1.33 result" "$TP" && grep -q "a turn-by-turn-only build" "$TP"'
for k in gpm dipo; do
    check "0.1.34 turns.py $k: an empty tree is refused (exit 1, nothing written)" eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-turns.XXXXXX"); python3 -I "$TP" '$k' "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
done
check "0.1.34 turns.sh: javac + d8 build Turns and TurnsOut only (Near is compiled against, not added), smali one thread, the 0.1.33 inputs named" \
    eval 'grep -q "smali-2.5.2.jar\" a -a 19 -j 1" "$P/src/tbt/turns.sh" && grep -q "rm -f \"\$work\"/classes/com/jmk/hud/Near\*.class" "$P/src/tbt/turns.sh" && grep -q "$B_GPM" "$P/src/tbt/turns.sh" && grep -q "$B_DIPO" "$P/src/tbt/turns.sh"'
if command -v javac >/dev/null 2>&1; then
    TJV=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-turns.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$TJV" "$TD/Turns.java" "$here/turns/com/jmk/hud/TurnsTest.java" 2>/dev/null; then
        out=$(java -cp "$TJV" com.jmk.hud.TurnsTest 2>&1 | tail -1)
        check "0.1.34 Turns on the JVM (every mapping row, before / after): $out" [ $? -eq 0 ]
        check "0.1.34 Turns on the JVM: every case passed" eval 'case "$out" in "turns: all "*) true ;; *) false ;; esac'
    else
        bad "0.1.34 Turns.java / TurnsTest.java compile"
    fi
    rm -rf "$TJV"
else
    echo "(no javac: the Turns test skipped)"
fi
for pr in kr:$T_GPM kra:$T_GPM krg:$T_GPM krt:$T_GPM kre:$T_GPM krp:$T_GPM kri:$T_GPM krb:$T_GPM krk:$T_GPM krc:$T_GPM_C krd:$T_GPM_C krm:$T_GPM_M krv:$T_GPM_M; do
    o=${pr%%:*}; gv=${pr#*:}
    lp=$(awk '$1=="2_tbt" && $3=="HKMC_GPM" {print $5}' "$PKG/patches/bycode/$o/manifest")
    check "0.1.34 $o: GPM ends at $gv; $lp ends there and carries Lcom/jmk/hud/TurnsOut; (and BarOut)" eval '[ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $gv ] && [ "$(lpd_dst "$PKG/patches/$lp")" = $gv ] && lpd_extra_has "$PKG/patches/$lp" "Lcom/jmk/hud/TurnsOut;" && lpd_extra_has "$PKG/patches/$lp" "Lcom/jmk/hud/BarOut;"'
done
for o in kr kra krg krt kre krp kri krb krk; do
    check "0.1.34 $o: DiPO bridge ends at $T_DIPO" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $T_DIPO ]
done
for lp in bycode/kr bycode/krb bycode/kre bycode/krp neev_kr; do
    check "0.1.34 $lp/HKMC_DiPO.bridge.lpd: ends at $T_DIPO and carries Lcom/jmk/hud/TurnsOut; (and Turns)" eval '[ "$(lpd_dst "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd")" = $T_DIPO ] && lpd_extra_has "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd" "Lcom/jmk/hud/TurnsOut;" && lpd_extra_has "$PKG/patches/'$lp'/HKMC_DiPO.bridge.lpd" "Lcom/jmk/hud/Turns;"'
done
check "0.1.34 neev_kr: GPM delta ends at $T_GPM (apk $FIN_GPM_APK), DiPO bridge delta at $T_DIPO (apk $FIN_DIPO_APK), Navi stays 0.1.33's ($B_NAVI, apk $B_NAVI_APK)" \
    eval '[ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_GPM.tbt.lpd")" = $T_GPM ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd")" = $T_DIPO ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_Navi_ExSL.tbt.lpd")" = $B_NAVI ] && grep -q "^2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd $FIN_GPM_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^2_tbt app HKMC_Navi_ExSL neev_kr/HKMC_Navi_ExSL.tbt.lpd $B_NAVI_APK$" "$PKG/patches/neev_kr/manifest"'
check "0.1.34 Navi, the turn-by-turn-only DiPO builds, the other fixed sets and us carry no Turns class" \
    eval 'for lp in "$PKG"/patches/*/HKMC_Navi_ExSL.tbt.lpd "$PKG"/patches/bycode/*/HKMC_Navi_ExSL.tbt*.lpd "$PKG"/patches/*/HKMC_DiPO.tbt.lpd "$PKG"/patches/bycode/*/HKMC_DiPO.tbt*.lpd "$PKG"/patches/bycode/us/*.lpd "$PKG"/patches/neev/*.lpd "$PKG"/patches/neev23_260903/*.lpd "$PKG"/patches/neev_ca/*.lpd "$PKG"/patches/ev6/*.lpd "$PKG"/patches/dl3hev/*.lpd "$PKG"/patches/nq5/*.lpd; do lpd_extra_has "$lp" "Lcom/jmk/hud/TurnsOut;"; [ $? -eq 1 ] || exit 1; done'
check "0.1.34 known: 0.1.33's results stay ours next to the new ones (GPM $B_GPM / $T_GPM, $B_GPM_C / $T_GPM_C, $B_GPM_M / $T_GPM_M, DiPO $B_DIPO / $T_DIPO, neev_kr apks $B_GPM_APK / $FIN_GPM_APK and $B_DIPO_APK / $FIN_DIPO_APK)" \
    eval 'for kv in HKMC_GPM.dex:$B_GPM HKMC_GPM.dex:$T_GPM HKMC_GPM.dex:$B_GPM_C HKMC_GPM.dex:$T_GPM_C HKMC_GPM.dex:$B_GPM_M HKMC_GPM.dex:$T_GPM_M HKMC_DiPO.dex:$B_DIPO HKMC_DiPO.dex:$T34_DIPO HKMC_GPM.apk:$B_GPM_APK HKMC_GPM.apk:$FIN_GPM_APK HKMC_DiPO.apk:$B_DIPO_APK HKMC_DiPO.apk:$T34_DIPO_APK HKMC_Navi_ExSL.apk:$B_NAVI_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done'
check "0.1.34 README: results first: what it supports, the cars, and the 0.1.34 / 0.1.33 results (hashes live in patches/, not the README)" \
    eval 'grep -q "^## What it supports" "$P/README.md" && grep -q "^## Where it comes from" "$P/README.md" && grep -q "^- \*\*0\.1\.34\*\*: " "$P/README.md" && grep -q "^- \*\*0\.1\.33\*\*: " "$P/README.md" && grep -q "AGPL-3.0" "$P/README.md" && grep -q "NOTICE.md" "$P/README.md"'
check "0.1.34 NOTICE: the AGPL-3.0 Korean-firmware mod code base is named as the source of the turn pictures, the bar and the near-turn fix" \
    eval '[ "$(grep -c "AGPL-3.0 Korean-firmware mod code base" "$P/NOTICE.md")" -ge 1 ] && grep -q "turn pictures (its 2.4.8 generation, AGPL-3.0)" "$P/NOTICE.md" && grep -q "phone bar (its 2.4.5 generation, AGPL-3.0)" "$P/NOTICE.md" && grep -q "near-turn fix (its 2.4.4 generation)" "$P/NOTICE.md"'
# 0.1.36: the turn-by-turn-only DiPO builds (no bridge part, no com/leafia) get the stock CarPlay table numbers back: cpstock.sh (cpstock.py edits
# eleven constants of u.a, each place exactly once), no class, no hook, no log line. Every other result stays 0.1.34's / 0.1.35's.
CS=$P/src/tbt/cpstock.py
for f in src/tbt/cpstock.py src/tbt/cpstock.sh; do
    check "0.1.36 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.1.36 cpstock.py: AGPL-3.0 header; eleven places (9: 0xac -> 0xa0, 22: 0x52 -> 0xa5, 23: 0x51 -> 0xa4, the eight left-hand roundabout rows to the 0xc0 family)" \
    eval 'grep -q "AGPL-3.0" "$CS" && [ "$(grep -c "^    (.[0-9lt]" "$CS")" = 11 ] && grep -q "0xac, 0xa0)" "$CS" && grep -q "0x52, 0xa5)" "$CS" && grep -q "0x51, 0xa4)" "$CS" && grep -q "0x60, 0xc0)" "$CS"'
check "0.1.36 cpstock.py: stops with status 1 when a place is not found exactly once, on a bridge build (com/leafia) and on the Turns hooks (the profile keeps its build)" \
    eval 'grep -q "found %d times (want 1)" "$CS" && grep -q "com/leafia" "$CS" && grep -q "already has the Turns hooks" "$CS" && grep -q "^import" "$CS" && ! grep -q "^import hmgapi" "$CS"'
check "0.1.36 cpstock.py: an empty tree is refused (exit 1, nothing written)" eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-cps0.XXXXXX"); python3 -I "$CS" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.1.36 cpstock.sh: baksmali, cpstock.py, smali one thread; no javac / d8 (no class is added)" \
    eval 'grep -q "baksmali-2.5.2.jar" "$P/src/tbt/cpstock.sh" && grep -q "cpstock.py" "$P/src/tbt/cpstock.sh" && grep -q "smali-2.5.2.jar\" a -a 19 -j 1" "$P/src/tbt/cpstock.sh" && ! grep -qE "^[^#]*(javac|d8)" "$P/src/tbt/cpstock.sh"'
check "0.1.36 the turn-by-turn-only DiPO deltas carry no Turns / TurnsOut / BarOut / Near class (nothing but table numbers changed)" \
    eval 'for lp in "$PKG"/patches/bycode/kr*/HKMC_DiPO.tbt.lpd "$PKG"/patches/neev_kr/HKMC_DiPO.tbt.lpd; do for c in TurnsOut Turns BarOut Near; do lpd_extra_has "$lp" "Lcom/jmk/hud/$c;"; [ $? -eq 1 ] || exit 1; done; done'
check "0.1.36 known: the 0.1.19 results stay ours next to the new turn-by-turn-only ones (HKMC_DiPO.dex krc $T19_C / $T36_C, krd $T19_D / $T36_D, krm krv $T19_M / $T36_M)" \
    eval 'for kv in HKMC_DiPO.dex:$T19_C HKMC_DiPO.dex:$C36_C HKMC_DiPO.dex:$T19_D HKMC_DiPO.dex:$C36_D HKMC_DiPO.dex:$T19_M HKMC_DiPO.dex:$C36_M; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done'
check "0.1.36 Lanes.java: the header keeps its line count (5 lines before the package line: attribution, repo and commit, file names, a plain // line), no car-test line in the header; class bytes are those of 0.1.35's (lanes.sh pins)" \
    eval '[ "$(sed -n 4p "$P/src/tbt/com/jmk/hud/Lanes.java")" = "//" ] && [ "$(sed -n 5p "$P/src/tbt/com/jmk/hud/Lanes.java")" = "package com.jmk.hud;" ] && sed -n 1,3p "$P/src/tbt/com/jmk/hud/Lanes.java" | grep -q "AGPL-3.0" && sed -n 1,3p "$P/src/tbt/com/jmk/hud/Lanes.java" | grep -q "fbaacf7" && ! sed -n 1,5p "$P/src/tbt/com/jmk/hud/Lanes.java" | grep -q "cluster-lane-arrows\|car-verified"'
check "0.1.36 README: the 0.1.36 line (Korean, result only) above 0.1.35's" \
    eval 'grep -q "^- \*\*0\.1\.36\*\*: 길안내만 설치된 차종에서도 카플레이 고속도로 진입 · 출구 그림이 순정 내비처럼 표시됩니다\.$" "$P/README.md" && [ "$(grep -n "^- \*\*0\.1\.36\*\*" "$P/README.md" | cut -d: -f1)" -lt "$(grep -n "^- \*\*0\.1\.35\*\*" "$P/README.md" | cut -d: -f1)" ]'
# 0.1.19: the turn-by-turn release at the end of the projection session and the com.jmk.hud.TBT_CLEAR receiver
# (src/tbt/tbt-clear.py on the smali tree + com/jmk/hud/TbtClear.java; src/tbt/clear.sh makes each 0.1.19 GPM / DiPO
# result from its 0.1.18 result): every GPM / DiPO result that carries our turn-by-turn patches changes, nothing else
TC=$P/src/tbt/tbt-clear.py; TJ=$P/src/tbt/com/jmk/hud/TbtClear.java
R019="$FIN_GPM $FIN_DIPO $P25_DIPO $P24_DIPO $P24_DIPOT $P24_C $P24_D $P24_M $P22_DIPO $P22_DIPOT $P22_C $P22_D $P22_M $T34_DIPO $T34_GPM $T21_DIPO $T34_GPM_C $T34_GPM_M $C36_F $C36_C $C36_D $C36_M $FIN_DIPOT $T36_C $T36_D $T36_M $T_GPM_C $T_GPM_M $B_GPM $B_DIPO $B_GPM_C $B_GPM_M d2538947dcd6a8af532e0fb2baf7be81 965c4bfa035f24caeba188d9450a7e35 7b0fb9800dc6479d466e06760942ea13 913848d61d675beb066e03f119a4cf6e 6dfde547549483ca65e822f5e992e275 e9b17e59a3231ffdc6b683f312957b10 be272d864b76d0dd0147c1fa64861164 9794821165c1037e0d15f13bb017289d $NEW_DIPO $FIN_DIPOT $T36_C $T36_D $T36_M"
R018="b02ada70f0de90a9e09d364a64559074 454c8dc4741bf9852e18a6a2ca27be23 1301c92348aab9290e5ee98f4b617cb4 56d9ff800ddc5a750fa2be6d247deb5d ffe9b558a288cdda39eabd92d4b5fccf fe5030232f629489d3249eb7c9ef1c05 f1c23b5fe21ba6898e1cf9339caf8906 29a4add9f184c91b163d9a8b864ce484"
for f in src/tbt/com/jmk/hud/TbtClear.java src/tbt/stubs/com/hkmc/cluster/NavigationCluster.java src/tbt/tbt-clear.py src/tbt/clear.sh; do
    check "0.1.19 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.1.19 TbtClear: the broadcast is com.jmk.hud.TBT_CLEAR (the 런처 메뉴's 계기판 길안내 지우기 sends it)" grep -q 'ACTION = "com.jmk.hud.TBT_CLEAR";' "$TJ"
check "0.1.19 TbtClear: registered at runtime once per process on the application context (no manifest change), senders need WRITE_SECURE_SETTINGS (root / system / shell)" \
    eval 'grep -q "app.registerReceiver(r, new IntentFilter(ACTION), \"android.permission.WRITE_SECURE_SETTINGS\", null);" "$TJ" && grep -q "context.getApplicationContext()" "$TJ" && grep -q "sOne != null" "$TJ"'
check "0.1.19 TbtClear: the owner's jmkClear first, the cluster directly only without a live owner; every path catches Throwable" \
    eval 'grep -q "getMethod(\"jmkClear\", Context.class).invoke(null, context)" "$TJ" && grep -q "if (!live) {" "$TJ" && [ "$(grep -c "catch (Throwable t)" "$TJ")" = 3 ]'
check "0.1.19 TbtClear.release: GPM's releaseGuidance cluster calls (destination \"\", TBT_INFO DisplayType 8, sub info cleared)" \
    eval 'grep -q "n.updateTBTInfo(8, 0, 0f, 0f, -1, 0, 0, 0, -1);" "$TJ" && grep -q "n.updateTBTSubInfo(0f, -1, 0, 0, 0, 0, 0, 0f, -1, 0);" "$TJ" && grep -q "d.name = \"\";" "$TJ"'
check "0.1.19 the NavigationCluster stub is compile-only (build.sh / clear.sh put only com/jmk into the dex)" \
    eval 'for s in build.sh clear.sh; do grep -q "\-cp \"\$work/stub\"" "$P/src/tbt/$s" && grep -q "\-\-classpath \"\$work/stub.jar\"" "$P/src/tbt/$s" || exit 1; done'
check "0.1.19 tbt-clear.py: GPM: destroy() (GalConnectionSession.clearSession, finalizeGal) runs jmkEnd -> onStatus(0) when this manager drew (mClaimed)" \
    eval 'grep -q "invoke-direct {p0}, %s->jmkEnd()V" "$TC" && grep -q "invoke-virtual {p0, v0}, {G}->onStatus(I)V" "$TC" && grep -q "iget v0, p0, {G}->mClaimed:I" "$TC"'
check "0.1.19 tbt-clear.py: GPM: stop() (also the navigation focus going to the native navigation) not hooked" eval '! grep -q "\.method public stop()V" "$TC"'
check "0.1.19 tbt-clear.py: DiPO: the end hook is in e/m.onSessionFinalized after u.disconnected(), not in the iAP2 listener e/a (comp 4 -> 5 handover)" \
    eval 'grep -q "com/daudio/app/dipo/e/m.smali" "$TC" && grep -q "e/u;->jmkEnd()V" "$TC" && ! grep -q "com/daudio/app/dipo/e/a.smali" "$TC"'
check "0.1.19 tbt-clear.py: DiPO: releases only when the last TBT_INFO it sent was not DisplayType 8 (jmkMark before the one send)" \
    eval 'grep -q "invoke-direct {p0, v1}, %s->jmkMark(I)V" "$TC" && grep -q "if-eq p1, v0, :cond_jmk_off" "$TC"'
check "0.1.19 tbt-clear.py: both services register the receiver at onCreate" [ "$(grep -c 'Lcom/jmk/hud/TbtClear;->register(Landroid/content/Context;Ljava/lang/Class;)V' "$TC")" = 2 ]
check "0.1.19 tbt-clear.py: stops with status 1 when an anchor is not found exactly once (the profile keeps its build)" grep -q "anchor found %d times (want %d)" "$TC"
check "0.1.19 build.sh: tbt-clear.py last, before smali" [ "$(grep -n 'tbt-clear.py' "$P/src/tbt/build.sh" | tail -1 | cut -d: -f1)" -lt "$(grep -n 'smali-2.5.2.jar" a ' "$P/src/tbt/build.sh" | cut -d: -f1)" ]
# every GPM / DiPO line of a by-code profile with our turn-by-turn code ends at a 0.1.19 result; no manifest names a
# 0.1.18 one; every such delta (and neev_kr's) carries TbtClear, no other set's does
for m in "$PKG"/patches/bycode/*/manifest; do
    prof=${m%/manifest}; prof=${prof##*/}; [ $prof = us ] && continue
    awk '$2=="app" && ($3=="HKMC_GPM" || $3=="HKMC_DiPO") {print $1" "$3" "$6}' "$m" | while read -r part app w; do
        echo "$R019" | tr ' ' '\n' | grep -qx "$w" || echo "FAILX $prof $part $app $w"
    done > "${TMPDIR:-/tmp}/jmk-hud-019.$$"
    check "0.1.19 $prof: every GPM / DiPO line ends at a 0.1.19 result" [ ! -s "${TMPDIR:-/tmp}/jmk-hud-019.$$" ]
    rm -f "${TMPDIR:-/tmp}/jmk-hud-019.$$"
done
check "0.1.19 no manifest names a 0.1.18 GPM / DiPO result" eval '! cat "$PKG"/patches/*/manifest "$PKG"/patches/bycode/*/manifest | grep -v "^#" | grep -qE "$(echo $R018 | tr " " "|")"'
for f in "$PKG"/patches/bycode/kr*/HKMC_GPM.tbt.lpd "$PKG"/patches/bycode/kr*/HKMC_DiPO.*.lpd "$PKG"/patches/neev_kr/HKMC_GPM.tbt.lpd "$PKG"/patches/neev_kr/HKMC_DiPO.*.lpd; do
    check "0.1.19 ${f#$PKG/patches/}: ends at a 0.1.19 result and carries TbtClear (TBT_CLEAR, jmkClear in its new bytes)" eval 'echo "$R019" | tr " " "\n" | grep -qx "$(lpd_dst "$f")" && lpd_extra_has "$f" "TBT_CLEAR" && lpd_extra_has "$f" "jmkClear"'
done
for f in "$PKG"/patches/bycode/us/HKMC_*.lpd "$PKG"/patches/{neev,neev_ca,neev23_260903,ev6,nq5,dl3hev}/HKMC_*.lpd; do
    check "0.1.19 ${f#$PKG/patches/}: no TbtClear (no turn-by-turn code of ours)" eval 'lpd_extra_has "$f" "TBT_CLEAR"; [ $? -eq 1 ]'
done
check "0.1.19 us: GPM / DiPO results unchanged" eval '[ "$(want_of "$PKG/patches/bycode/us/manifest" 2_tbt HKMC_GPM)" = 6124a666b2ae11883e91de85c19389d2 ] && [ "$(want_of "$PKG/patches/bycode/us/manifest" 2_tbt HKMC_DiPO)" = 3ed14600c11c6bf661515000ceec3544 ]'
for sg in neev:0308224b94c7e1b81d372a8ea1535aed neev23_260903:7f69ea05602f6ab9d5ce4da432e2a1d1 neev_ca:e99223a2f17723660345205242054b12 \
          ev6:7c6df0f570677157326b105b6b87bfc2 ev6_ca:1929356d4d7126b28ffd3a6f13392fcf dl3hev:08a29f343fbdb2abc7e11eb8a5698653 nq5:429a1205e0d7430a04c9b08d1c64c78b; do
    check "0.1.19 ${sg%%:*}: GPM build unchanged (${sg#*:})" eval '[ "$(awk '"'"'$1=="2_tbt" && $3=="HKMC_GPM" {print $5}'"'"' "$PKG/patches/${sg%%:*}/manifest")" = ${sg#*:} ]'
done
hin 10
hin 11
check "by code: the profile with the most parts wins (bycode_build tries both parts first)" grep -q 'for want in 2 1' "$PKG/scripts/common.sh"
while read -r pre set name; do
    case "$pre" in ''|'#'*) continue ;; esac
    check "cars: $pre -> $set exists" [ -f "$PKG/patches/$set/manifest" ]
done < "$PKG/patches/cars"
for f in "$PKG"/patches/*/knobs; do
    keys=$(grep -v '^#' "$f" | tr ' ' '\n' | grep .)
    for k in $keys; do check "knobs ${f#$PKG/}: $k has a switch in common.sh" eval 'case "$k" in log|lane_dist|cp_lanes|cp_keepbt) true ;; *) false ;; esac'; done
done
check "neev_kr: 6 targets (GPM, Navi, lib from 2_tbt; Iap2, DiPO, PhoneProjection from 3_bridge)" \
    [ "$(effective neev_kr | while read -r a b c d e; do echo "$a:$c"; done | tr '\n' ' ')" = "2_tbt:HKMC_GPM 2_tbt:HKMC_Navi_ExSL 2_tbt:libautoreceiver_infobank.so 3_bridge:Iap2ServerApp 3_bridge:HKMC_DiPO 3_bridge:PhoneProjection " ]
if [ -f "$LEAFIA_LC/stock.md5" ] && [ -f "$LEAFIA_LC/final.md5" ]; then
    while read -r f s; do
        want=$(grep -E " (app|lib)/$f\$" "$LEAFIA_LC/stock.md5" | cut -d' ' -f1)
        check "neev_kr stock $f = Leafia KR stock.md5" [ "$want" = "$s" ]
    done < "$PKG/patches/neev_kr/stock"
    while read -r a b c d e; do
        [ "$b" = app ] && f=app/$c.apk || f=lib/$c
        fin=$(grep " $f\$" "$LEAFIA_LC/final.md5" | cut -d' ' -f1)
        # 0.1.5: GPM and DiPO carry our guidance-end fix (TBT_INFO DisplayType 8, not 0: the cluster spun), 0.1.11 the
        # near-turn filter (src/tbt), DiPO 0.1.13 the wireless iAP2 fix, so their results are Leafia KR's plus those
        # changes; every other target is still Leafia KR's byte for byte
        case "$c" in HKMC_GPM|HKMC_DiPO|HKMC_Navi_ExSL) check "neev_kr result $c is ours (0.1.5 guidance-end fix, 0.1.11 near-turn filter, DiPO 0.1.13 wireless iAP2 and 0.1.18 CarPlay-channel resume, 0.1.19 TBT clear, 0.1.33 distance bar, 0.1.34 turn pictures), not Leafia KR's" [ "$fin" != "$e" ]; continue ;; esac
        check "neev_kr result $c = what Leafia KR leaves on the car (final.md5 $f)" [ "$fin" = "$e" ]
    done < <(effective neev_kr)
else
    echo "(Leafia's KR md5 lists not on this Mac: skipped)"
fi
hin 12
hin 13
for r in "$PKG"/recipes/*.recipe; do
    check "recipe ${r##*/}: id and file lines" eval 'grep -q "^id " "$r" && grep -q "^file /system/lib/" "$r"'
done
check "lpatch is Leafia 1.0.5's (sha256 b11077ab…)" [ "$(shasum -a 256 "$PKG/tools/lpatch" | cut -d' ' -f1)" = b11077ab6bbba7a2dbed225340d06db46c843a667a3813f894f2927ec61c2bb6 ]
check "libev6aac.so is Leafia's (md5 = CONV_SUM)" [ "$(md5 -q "$PKG/files/libev6aac.so")" = "$(grep -o 'CONV_SUM=[0-9a-f]*' "$PKG/scripts/common.sh" | cut -d= -f2)" ]
check "version: NEMESIS.data package-version 0.2.6" grep -q '^package-version=0.2.6$' "$PKG/NEMESIS.data"
before=$(shasum -a 256 "$PKG/tools/codesum.jar" | cut -d' ' -f1)
if bash "$P/src/build-codesum.sh" >/dev/null 2>&1; then
    check "tools/codesum.jar is the build of src/jmkhud/CodeSum.java (src/build-codesum.sh gives the same bytes)" [ "$(shasum -a 256 "$PKG/tools/codesum.jar" | cut -d' ' -f1)" = "$before" ]
fi
check "NOTICE names tools/codesum.jar with its sha256" grep -q "$before" "$P/NOTICE.md"
check "0.2.6 NEMESIS.data depends: jmk-autoplay stays, the three packages that also edit these /system files are refused in both install orders (!id); the preinstall refusal of Danpung stays" \
    eval 'D=$(sed -n "s/^depends=\"\(.*\)\"$/\1/p" "$PKG/NEMESIS.data"); [ "$D" = "jmk-autoplay,!danpung,!enhanced.projection,!wireless.carplay.aa" ] && grep -q "other=\$(other_projection)" "$PKG/scripts/preinstall.sh" && grep -q "danpung\*" "$PKG/scripts/common.sh"'
check "NEMESIS.data: id, depends, os" eval 'grep -q "^id=jmk-autoplay-hud$" "$PKG/NEMESIS.data" && grep -q "^depends=\"jmk-autoplay,!danpung,!enhanced.projection,!wireless.carplay.aa\"$" "$PKG/NEMESIS.data" && grep -q "^os=\"\*.KOR.\*\"$" "$PKG/NEMESIS.data"'

# 0.1.37: the frame wait of libCarPlayCore (recipes/carplay-core-frames-ef49c09b.recipe, from the Open-HMG wireless mod, AGPL-3.0, tag v2.2.0-rc.9
# commit f657ca4): written only to the stock ef49c09b (recipes/gates: whole-file md5 before, result md5 after), five bytes, put back on uninstall
FR=$PKG/recipes/carplay-core-frames-ef49c09b.recipe; CORE_STOCK=ef49c09b7ab5eb72298f9973443b66b3; CORE_FRAMES=36c65d80ea46f833f84c7567f43ffc2b
check "0.1.37 frames recipe: the lines below the attribution header are upstream's byte for byte (md5 8e78af9e…)" eval '[ "$(tail -n +7 "$FR" | md5 -q)" = 8e78af9eb62bad729a5be28e4d2fff64 ] && [ "$(sed -n 1,6p "$FR" | grep -c "^#")" = 6 ]'
check "0.1.37 frames recipe header: AGPL-3.0, the Open-HMG repo, the tag, commit f657ca4, the file, issue #25 / pull request #26" \
    eval 'sed -n 1,6p "$FR" | grep -q "AGPL-3.0" && sed -n 1,6p "$FR" | grep -q "github.com/Open-HMG/hmgapi-wireless-cp-aa" && sed -n 1,6p "$FR" | grep -q "v2.2.0-rc.9" && sed -n 1,6p "$FR" | grep -q "f657ca4" && sed -n 1,6p "$FR" | grep -q "carplay-core-frames-ef49c09b.recipe" && sed -n 1,6p "$FR" | grep -q "#25" && sed -n 1,6p "$FR" | grep -q "#26"'
check "0.1.37 frames recipe: id, the library, one verify of 42 bytes at 0x1482a, two patches (0x1483a 0a, 0x14840 c0f20007), no native line" \
    eval '[ "$(grep -v "^#" "$FR" | tr "\n" "|")" = "id carplay-core-frames-ef49c09b|file /system/lib/libCarPlayCore.so|verify 0x1482a 42 f167a8b61d9bbfe2a86eb973668a8abd 18c301cd2a43825630dbb44810b3d7fd|patch 0x1483a 0a|patch 0x14840 c0f20007|" ]'
check "0.1.37 recipes/gates: the data lines (0.3.3 adds the lane recipe), the stock md5 $CORE_STOCK and the result md5 $CORE_FRAMES" \
    eval '[ "$(grep -v "^#" "$PKG/recipes/gates" | tr "\n" "|")" = "carplay-core-frames-ef49c09b $CORE_STOCK $CORE_FRAMES|carplay-lanes-iap2 fc7cb675b46a44bd893a1edc054c5e71 4ce639fea732b1ec052407d0b5548c42|" ]'
check "0.1.37 NOTICE: the Open-HMG wireless mod, AGPL-3.0, tag v2.2.0-rc.9, commit f657ca4, issue #25 and pull request #26" \
    eval 'grep -q "Open-HMG/hmgapi-wireless-cp-aa" "$P/NOTICE.md" && grep -q "v2.2.0-rc.9" "$P/NOTICE.md" && grep -q "f657ca4" "$P/NOTICE.md" && grep -q "pull request #26" "$P/NOTICE.md"'
check "0.1.37 common.sh: the frames recipe is listed before carplay-core-wifi; the gate is read from recipes/gates before building and after (stock md5, result md5), one recipe writes a file once" \
    eval 'grep -q "^RECIPE_IDS=\"carplay-utils-converter carplay-audio-formats carplay-core-frames-ef49c09b carplay-core-wifi\"$" "$PKG/scripts/common.sh" && grep -q "gs=\$(recipe_gate \"\$id\" 1)" "$PKG/scripts/common.sh" && grep -q "gr=\$(recipe_gate \"\$1\" 2)" "$PKG/scripts/common.sh" && grep -q "is taken by another recipe of this run: skipped" "$PKG/scripts/common.sh"'
check "0.1.37 README: the 0.1.37 line (Korean, result only) above 0.1.36's" \
    eval 'grep -q "^- \*\*0\.1\.37\*\*: 카플레이 영상이 잠깐 끊겨도 연결이 유지됩니다\.$" "$P/README.md" && [ "$(grep -n "^- \*\*0\.1\.37\*\*" "$P/README.md" | cut -d: -f1)" -lt "$(grep -n "^- \*\*0\.1\.36\*\*" "$P/README.md" | cut -d: -f1)" ]'
hin 14
frames_bytes() {   # frames_bytes <stock> <patched>: ok when the files differ in exactly the five bytes of the recipe (and in nothing else)
    python3 -I - "$1" "$2" <<'PY'
import sys
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
d = [(i, a[i], b[i]) for i in range(min(len(a), len(b))) if a[i] != b[i]]
print('ok' if len(a) == len(b) and d == [(0x1483a, 0x00, 0x0a), (0x14840, 0xcf, 0xc0), (0x14841, 0xf6, 0xf2), (0x14842, 0xff, 0x00), (0x14843, 0x77, 0x07)] else 'differs')
PY
}
hin 15

# 0.1.38: firmware changed after the install: an .odex is ours by its own md5 (made list) first, and on a changed firmware only so;
# a saved stock copy is never written over a file that is neither ours nor the saved stock md5 (common.sh ours / restore_files / fw_reconcile)
check "0.1.38 common.sh ours(): the .odex branch asks its own md5 in the made list first, then stops on a changed firmware before it looks at the apk" \
    eval '[ "$(grep -n "\[ -n \"\$2\" \] && made \"\$f\" \"\$2\" && return 0" "$PKG/scripts/common.sh" | cut -d: -f1)" -lt "$(grep -n "fw_changed && return 1" "$PKG/scripts/common.sh" | cut -d: -f1)" ] && [ "$(grep -n "fw_changed && return 1" "$PKG/scripts/common.sh" | cut -d: -f1)" -lt "$(grep -n "apk=\${f%.odex}.apk" "$PKG/scripts/common.sh" | cut -d: -f1)" ]'
check "0.1.38 common.sh: fw_reconcile and restore_files report firmware-changed (left as it is) for a file they leave alone" \
    eval '[ "$(grep -c "report firmware-changed \"left as it is: " "$PKG/scripts/common.sh")" = 2 ]'

# 0.1.38 krq: the Kia Sportage Hybrid Korea NQ5HEV V038 (260604), turn-by-turn only: its GPM / DiPO / Navi are the Ioniq 5 KR's stock code with other
# ProGuard names (every method body equal after the names, quickened numbers and one sibling-class swap per app are taken out;
# resource ids and manifest components equal), Iap2ServerApp is kr's own code; each result is kr's turn-by-turn build. No bridge part (its framework and
# PhoneProjection files were not uploaded to prove a bridge_framework line), no library line (its library was not uploaded).
KRQ=$PKG/patches/bycode/krq/manifest; KRM_K=$PKG/patches/bycode/kr/manifest
check "by code krq: turn-by-turn only, the four apps, no library line, no 3_bridge part" [ "$(grep -v '^#' "$KRQ" | awk '{print $1":"$2":"$3}' | tr '\n' ' ')" = "2_tbt:app:HKMC_GPM 2_tbt:app:HKMC_DiPO 2_tbt:app:Iap2ServerApp 2_tbt:app:HKMC_Navi_ExSL " ]
for ac in HKMC_GPM:8c2212bebf060b63fd38b45c8a8ba8b6:bycode/krq/HKMC_GPM.tbt.lpd HKMC_DiPO:cc5bb96db24da52d3be95e1935bd3ba8:bycode/krq/HKMC_DiPO.tbt.lpd \
          Iap2ServerApp:30a34f8331e3c74a18c0241a28a036ea:bycode/kr/Iap2ServerApp.tbt.lpd HKMC_Navi_ExSL:fa14c57c7106da3da796e2a0b37f70ae:bycode/krq/HKMC_Navi_ExSL.tbt.lpd; do
    qa=${ac%%:*}; qr=${ac#*:}; qc=${qr%%:*}; qp=${qr#*:}
    check "by code krq: $qa is NQ5HEV V038's code ($qc) -> $qp, kr's own turn-by-turn result $(want_of "$KRM_K" 2_tbt $qa)" \
        eval '[ "$(awk -v n=$qa '"'"'$1=="2_tbt" && $3==n {print $4" "$5" "$6}'"'"' "$KRQ")" = "$qc $qp $(want_of "$KRM_K" 2_tbt $qa)" ] && [ -s "$PKG/patches/$qp" ]'
    for o in kr kra krb krc krd kre krg kri krk krm krp krt krv us; do
        check "by code krq: $qa's code is no other profile's ($o)" eval '[ "$qa" = Iap2ServerApp ] || ! grep -q " $qa $qc " "$PKG/patches/bycode/$o/manifest"'
    done
done
check "by code krq: Iap2ServerApp is kr's line word for word (the same code, kr's delta)" [ "$(grep '^2_tbt app Iap2ServerApp ' "$KRQ")" = "$(grep '^2_tbt app Iap2ServerApp ' "$KRM_K")" ]
check "by code krq: the knobs are kr's without the Bluetooth key (only the bridge builds read it)" eval '[ "$(grep -v "persist.leafia.cp.keepbt" "$PKG/patches/bycode/kr/knobs" | sed "s/ cp_keepbt//")" = "$(cat "$PKG/patches/bycode/krq/knobs")" ]'
check "by code choice (0.1.38): a Sportage Hybrid V038 car (O3IH3AVV's codes, its own PhoneProjection) gets krq, turn-by-turn only (the library does not matter: no line)" \
    eval '[ "$(sel_of 8c2212bebf060b63fd38b45c8a8ba8b6 cc5bb96db24da52d3be95e1935bd3ba8 30a34f8331e3c74a18c0241a28a036ea fa14c57c7106da3da796e2a0b37f70ae 2c9636333884e579733d40ed5f7fd14a $LIB_KR)" = "krq 2_tbt" ] && [ "$(sel_of 8c2212bebf060b63fd38b45c8a8ba8b6 cc5bb96db24da52d3be95e1935bd3ba8 30a34f8331e3c74a18c0241a28a036ea fa14c57c7106da3da796e2a0b37f70ae 2c9636333884e579733d40ed5f7fd14a 0123456789abcdef0123456789abcdef)" = "krq 2_tbt" ]'
check "by code choice (0.1.38): the Sportage Hybrid's GPM code with kr's DiPO code fits nothing (every line of the part must match)" [ "$(sel_of 8c2212bebf060b63fd38b45c8a8ba8b6 7abefa3e86fddc50e6cd27e32dc16fb3 30a34f8331e3c74a18c0241a28a036ea fa14c57c7106da3da796e2a0b37f70ae 2c9636333884e579733d40ed5f7fd14a $LIB_KR)" = none ]
check "by code choice (0.1.38): the other cars keep their profiles (Ioniq 5 Korea V039 kr, CN7 PE krp)" eval '[ "$(sel_of 4b4c021c4f58cf5f5aae76e33f9151f5 7abefa3e86fddc50e6cd27e32dc16fb3 30a34f8331e3c74a18c0241a28a036ea 41aa4615841d24e23faf02be05fca29f d89764a2b7aa475badb9d3c28e3aecc3 $LIB_KR)" = "kr 2_tbt 3_bridge" ] && [ "$(sel_of 2487f61fcbae1a779fd92271c7a0360e ce035a13280e222b919d664677928538 30a34f8331e3c74a18c0241a28a036ea bc5ac4a4672362651fb0e523e68f01d3 4ddd81e7e095073156c1130449fdafed dbfe7bd2000000000000000000000000)" = "krp 2_tbt 3_bridge" ]'
hin 16
hin 17

check "0.1.38 README: the 0.1.38 line (Korean, result only) above 0.1.37's; the Sportage Hybrid is in the car list" \
    eval 'grep -q "^- \*\*0\.1\.38\*\*: 펌웨어를 업데이트한 차에서 삭제 · 업데이트할 때 순정 파일을 예전 것으로 되돌리지 않습니다\. 스포티지 하이브리드(이전 펌웨어 V038)에서 계기판 · HUD 길안내가 설치됩니다\.$" "$P/README.md" && [ "$(grep -n "^- \*\*0\.1\.38\*\*" "$P/README.md" | cut -d: -f1)" -lt "$(grep -n "^- \*\*0\.1\.37\*\*" "$P/README.md" | cut -d: -f1)" ] && grep -q "Sportage Hybrid NQ5HEV" "$P/README.md"'
check "0.1.38 known: the krq results are ours (HKMC_DiPO.dex f1213499…, a turn-by-turn-only profile's)" grep -qx "HKMC_DiPO.dex f121349937ec0b2af47837c2ba6664c8" "$PKG/patches/known"

# ---------------------------------------------------------------- 0.2.0: the DiPO bridge asks the local JMK service before it starts the car hotspot
# (src/tbt/callout.sh: callout.py on Bridge.ensureHotspot + com/jmk/hud/Callout.java + the client copy in src/callout/). Every DiPO bridge result
# changes (7aa7e009 -> FIN_DIPO); nothing else does. The tbt-only DiPO builds, the market sets and every GPM / Navi / Iap2 / PhoneProjection result stay.
CO=$P/src/tbt/callout.py
for f in src/tbt/callout.py src/tbt/callout.sh src/tbt/com/jmk/hud/Callout.java src/callout/jmkhud/link/HookClient.java src/callout/jmkhud/link/Wire.java \
         src/callout/jmkhud/link/Frame.java src/callout/jmkhud/link/Helper.java src/callout/jmkhud/link/Gate.java src/callout/jmkhud/link/Lex.java src/callout/jmkhud/link/Transport.java \
         src/callout/jmkhud/link/Clock.java src/callout/jmkhud/link/Log.java \
         src/callout/jmkhud/link/ReadTimeout.java src/callout/jmkhud/link/android/LocalSockets.java; do
    check "0.2.0 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.2.6 version: package-version 0.2.6 (the legacy package), the README 0.2.6 line directly above the 0.2.5 line (the LivePatch lines 0.3.x come before them)" \
    eval '[ "$(sed -n "s/^package-version=//p" "$PKG/NEMESIS.data")" = 0.2.6 ] && [ "$(grep "^- \*\*0\.2\.6\*\*" "$P/README.md" | wc -l | tr -d " ")" = 1 ] && [ "$(grep -A1 "^- \*\*0\.2\.6\*\*" "$P/README.md" | sed -n 2p | cut -c1-11)" = "- **0.2.5**" ]'
check "0.2.0 callout.py: AGPL-3.0 header; one anchor; stops with status 1 when it is not there once, when Callout is not in the tree, and when the call-out is in already" \
    eval 'grep -q "AGPL-3.0" "$CO" && grep -q "found %d times (want 1)" "$CO" && grep -q "already has the call-out" "$CO" && grep -q "is not in the tree" "$CO" && grep -q "^import" "$CO" && ! grep -q "^import hmgapi" "$CO"'
check "0.2.0 callout.py: an empty tree is refused (exit 1, nothing written)" eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-co0.XXXXXX"); python3 -I "$CO" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.2.0 callout.sh: javac + d8 for the classes, baksmali, callout.py, smali one thread; no other tool" \
    eval 'grep -q "baksmali-2.5.2.jar" "$P/src/tbt/callout.sh" && grep -q "callout.py" "$P/src/tbt/callout.sh" && grep -q "smali-2.5.2.jar\" a -a 19 -j 1" "$P/src/tbt/callout.sh" && grep -q "callout/jmkhud/link" "$P/src/tbt/callout.sh"'
hin 18
check "0.2.0 every DiPO bridge delta ends at $FIN_DIPO and carries Callout, HookClient and Helper (Korean bridge builds)" \
    eval '( for lp in neev_kr bycode/kr bycode/krb bycode/kre bycode/krp; do [ "$(lpd_dst "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd")" = $FIN_DIPO ] || exit 1; for c in "Lcom/jmk/hud/Callout;" "Ljmkhud/link/HookClient;" "Ljmkhud/link/Helper;"; do lpd_extra_has "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd" "$c"; [ $? -eq 0 ] || exit 1; done; done )'
check "0.2.0 the nine DiPO bridge profiles (neev_kr kr kra krb kre krg kri krk krp krt) end at $FIN_DIPO, in neev_kr as apk $FIN_DIPO_APK" \
    eval '( for o in kr kra krb kre krg kri krk krp krt; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ] || exit 1; done; grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest" )'
check "0.2.0 no other result changed: the turn-by-turn-only DiPO deltas, every GPM / Navi / Iap2 / PhoneProjection delta and the market sets carry no Callout class" \
    eval '( for lp in "$PKG"/patches/*/*.lpd "$PKG"/patches/bycode/*/*.lpd; do case "$lp" in */HKMC_DiPO.bridge.lpd) case "$lp" in */neev_kr/*|*/bycode/kr/*|*/bycode/krb/*|*/bycode/kre/*|*/bycode/krp/*) continue;; esac;; esac; lpd_extra_has "$lp" "Lcom/jmk/hud/Callout;"; [ $? -eq 1 ] || { echo "$lp"; exit 1; }; done )'
check "0.2.0 known: the 0.1.34 bridge results stay ours next to the new ones (dex $T34_DIPO / $FIN_DIPO, neev_kr apk $T34_DIPO_APK / $FIN_DIPO_APK)" \
    eval '( for kv in HKMC_DiPO.dex:$T34_DIPO HKMC_DiPO.dex:$FIN_DIPO HKMC_DiPO.apk:$T34_DIPO_APK HKMC_DiPO.apk:$FIN_DIPO_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done )'
check "0.2.0 Callout.java: no flush() and no socket of its own: the transport is jmkhud.link.android.LocalSockets (no flush, bounded writes), copied byte for byte" \
    eval 'J=$P/src/tbt/com/jmk/hud/Callout.java; ! grep -v "^ *//" "$J" | grep -q "\.flush()" && grep -q "LocalSockets.connector(NAME)" "$J" && ! grep -q "LocalSocket\b" "$J"'
check "0.2.0 known: the earlier DiPO results (0.2.0's published 5eb801b6 / apk 2073eabc, the test builds c1e236dd, 3838ee7d, d0825bae with apks 451cb07b, 0042851e, 60484003) stay ours next to 0.2.1's" \
    eval 'for kv in HKMC_DiPO.dex:c1e236ddc6c9bd915c83ae51df7ae73b HKMC_DiPO.dex:3838ee7d4a7dca850d015fd3a4568c5d HKMC_DiPO.apk:451cb07b8cf553a61d3c4b1dff41f93f HKMC_DiPO.apk:0042851ef96244d6125f8f60c9d0b88b HKMC_DiPO.dex:5eb801b6f951de193d2c1a2f6a0542ba HKMC_DiPO.apk:2073eabc2ae9755e85d15115f664a29a HKMC_DiPO.dex:d0825bae5703b343f81364e857e06505 HKMC_DiPO.apk:60484003247606c14e59b679e589385a; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done'
hin 19
hin 20
hin 21
# ---------------------------------------------------------------- 0.2.2: Android Auto guidance is not switched off by silence (guide.sh), the lengths of the texts handed to the cluster go into the log (textlog.sh)
for f in src/tbt/guide.py src/tbt/guide.sh src/tbt/textlog.py src/tbt/textlog.sh src/tbt/com/jmk/hud/TextLog.java; do
    check "0.2.2 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
for gp in guide textlog; do
    check "0.2.2 $gp.py: AGPL-3.0 header; stops with status 1 on an empty tree and when the edit is there already (nothing written)" \
        eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-gp.XXXXXX"); python3 -I "$P/src/tbt/$gp.py" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; grep -q "AGPL-3.0" "$P/src/tbt/$gp.py" && grep -q "already" "$P/src/tbt/$gp.py" && [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
done
check "0.2.2 TextLog.java: only lengths are logged (no text in the log call), never throws, one line per change of a site's lengths" \
    eval 'T=$P/src/tbt/com/jmk/hud/TextLog.java; grep -q "Log.i(TAG, \"Text: \" + site + \" chars=\"" "$T" && ! grep -q "Log.i(TAG, .*[^a-z]s)" "$T" && grep -q "catch (Throwable t)" "$T" && grep -q "now.equals(LAST.get(site))" "$T"'
check "0.2.2 the new GPM and DiPO results (kr family 157a712e / c2165b59 / tbt 35711f75, krc, krd, krm) are in the manifests of every Korean profile and neev_kr; the 0.2.1 results stay in known" \
    eval '( for o in kr kra krb kre krg kri krk krp krt krq; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $FIN_GPM ] || exit 1; done; for o in krc krd; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $T_GPM_C ] || exit 1; done; for o in krm krv; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $T_GPM_M ] || exit 1; done; for o in kr kra krb kre krg kri krk krp krt; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ] || exit 1; done; for kv in HKMC_GPM.dex:$T34_GPM HKMC_GPM.dex:$T34_GPM_C HKMC_GPM.dex:$T34_GPM_M HKMC_DiPO.dex:$T21_DIPO HKMC_DiPO.apk:$T21_DIPO_APK HKMC_GPM.apk:$T21_GPM_APK HKMC_DiPO.dex:$FIN_DIPO HKMC_DiPO.dex:$FIN_DIPOT HKMC_DiPO.dex:$T36_C HKMC_DiPO.dex:$T36_D HKMC_DiPO.dex:$T36_M HKMC_GPM.dex:$FIN_GPM HKMC_GPM.apk:$FIN_GPM_APK HKMC_DiPO.apk:$FIN_DIPO_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done )'
# ---------------------------------------------------------------- 0.2.4: CarPlay guidance is not switched off by silence (cpend.sh), each blank of the cluster's turn-by-turn is named in the log
for f in src/tbt/cpend.py src/tbt/cpend.sh src/tbt/com/jmk/hud/EndLog.java; do
    check "0.2.4 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.2.4 cpend.py: AGPL-3.0 header; stops with status 1 on an empty tree and when the edit is there already (nothing written)" \
    eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-gp.XXXXXX"); python3 -I "$P/src/tbt/cpend.py" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; grep -q "AGPL-3.0" "$P/src/tbt/cpend.py" && grep -q "already" "$P/src/tbt/cpend.py" && [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.2.4 EndLog.java: one line naming the path, no text and no route data, never throws, only short stock method names and two fixed names are written" \
    eval 'T=$P/src/tbt/com/jmk/hud/EndLog.java; grep -q "Log.i(TAG, \"Guide end: CarPlay turn-by-turn blanked by \" + why)" "$T" && grep -q "catch (Throwable t)" "$T" && grep -q "n.length() <= 3" "$T" && [ "$(grep -c "Log\." "$T")" = 1 ]'
check "0.2.5 the new DiPO results (bridge $FIN_DIPO; turn-by-turn-only $FIN_DIPOT, krc $T36_C, krd $T36_D, krm krv $T36_M) are in the manifests of every Korean profile and neev_kr (apks $FIN_DIPO_APK / $FIN_DIPOT_APK); the 0.2.2 and 0.2.4 results stay in known" \
    eval '( for o in kr kra krb kre krg kri krk krp krt; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ] || exit 1; [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_DiPO)" = $FIN_DIPOT ] || exit 1; done; [ "$(want_of "$PKG/patches/bycode/krq/manifest" 2_tbt HKMC_DiPO)" = $FIN_DIPOT ] || exit 1; [ "$(want_of "$PKG/patches/bycode/krc/manifest" 2_tbt HKMC_DiPO)" = $T36_C ] || exit 1; [ "$(want_of "$PKG/patches/bycode/krd/manifest" 2_tbt HKMC_DiPO)" = $T36_D ] || exit 1; for o in krm krv; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_DiPO)" = $T36_M ] || exit 1; done; grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^2_tbt app HKMC_DiPO neev_kr/HKMC_DiPO.tbt.lpd $FIN_DIPOT_APK$" "$PKG/patches/neev_kr/manifest" && for kv in HKMC_DiPO.dex:$P22_DIPO HKMC_DiPO.dex:$P22_DIPOT HKMC_DiPO.dex:$P22_C HKMC_DiPO.dex:$P22_D HKMC_DiPO.dex:$P22_M HKMC_DiPO.apk:$P22_DIPO_APK HKMC_DiPO.dex:$P25_DIPO HKMC_DiPO.apk:$P25_DIPO_APK HKMC_DiPO.dex:$P24_DIPO HKMC_DiPO.dex:$P24_DIPOT HKMC_DiPO.dex:$P24_C HKMC_DiPO.dex:$P24_D HKMC_DiPO.dex:$P24_M HKMC_DiPO.apk:$P24_DIPO_APK HKMC_DiPO.dex:$FIN_DIPO HKMC_DiPO.dex:$FIN_DIPOT HKMC_DiPO.apk:$FIN_DIPO_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done )'
check "0.2.5 source src/tbt/com/jmk/hud/Keep.java in the package (TOP_FILES)" eval '[ -s "$P/src/tbt/com/jmk/hud/Keep.java" ] && grep -q "src/tbt/com/jmk/hud/Keep.java" "$P/build_nemesis_package.py"'
check "0.2.5 Keep.java: the approved sentence is in its header, letter for letter; every hook is inside try / catch Throwable; no reflection beyond the two stock names and Callout.busy" \
    eval 'K=$P/src/tbt/com/jmk/hud/Keep.java; grep -qF -- "HUD DiPO bridge: a local JMK service (\`jmk.core\`) decides how the route display proceeds." "$K" && [ "$(grep -c "catch (Throwable t)" "$K")" -ge 8 ] && [ "$(grep -c "Class.forName(" "$K")" = 2 ]'
check "0.2.5 Keep.java: the words on the wire are the pinned ones (Lex.KEEP_ASK / KEEP_NOTE, keys src why st quiet_ms since_state_ms n refresh can_refresh, src st since_state_ms reason), the service name jmk.core, role hud-dipo" \
    eval 'K=$P/src/tbt/com/jmk/hud/Keep.java; for w in "Lex.KEEP_ASK" "Lex.KEEP_NOTE" \"quiet_ms\" \"since_state_ms\" \"can_refresh\" \"refresh\" \"reason\" \"jmk.core\" \"hud-dipo\"; do grep -q "$w" "$K" || exit 1; done'
check "0.2.5 Keep.java: the question's budget is 300 ms; notes at most one a second and 60 an hour" \
    eval 'K=$P/src/tbt/com/jmk/hud/Keep.java; grep -q "ASK_MS = 300" "$K" && grep -q "NOTE_GAP_MS = 1000" "$K" && grep -q "NOTE_HOUR_MAX = 60" "$K"'
check "0.3.2 source src/tbt/com/jmk/hud/Evt.java in the package (TOP_FILES); cpend.sh compiles it" eval '[ -s "$P/src/tbt/com/jmk/hud/Evt.java" ] && grep -q "src/tbt/com/jmk/hud/Evt.java" "$P/build_nemesis_package.py" && grep -q "com/jmk/hud/Evt.java" "$P/src/tbt/cpend.sh"'
check "0.3.2 Keep.java: no timer thread (main-looper Handler), no time or failure count decides an end: only an answer drop ends (zero keeps on none; due ends only on DROP), the question and the note have their own client" \
    eval 'K=$P/src/tbt/com/jmk/hud/Keep.java; ! grep -q "java.util.Timer" "$K" && grep -q "postDelayed" "$K" && grep -q "if (act == DROP)" "$K" && ! grep -q "act == DROP || act == NONE" "$K" && grep -q "client(true)" "$K" && grep -q "client(false)" "$K" && ! grep -q "HookClient.get(" "$K"'
for f in src/tbt/evt.py src/tbt/evt.sh; do
    check "0.3.2 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.3.2 evt.py: AGPL-3.0 header; stops with status 1 on an empty tree and when the edit is there already (nothing written); the three hand-overs, the source store and the restart call are each found exactly once" \
    eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-gp.XXXXXX"); python3 -I "$P/src/tbt/evt.py" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; grep -q "AGPL-3.0" "$P/src/tbt/evt.py" && grep -q "already" "$P/src/tbt/evt.py" && grep -q "(want 1)" "$P/src/tbt/evt.py" && [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.3.2 evt.py hooks: Iap2SvcTransportReadDone x3 (Evt.iapIn), the source name store (Evt.source), LeafiaRgRestart.run (Evt.restart): no other place, no timer" \
    eval 'E=$P/src/tbt/evt.py; [ "$(grep -c "Evt;->" "$E")" -ge 3 ] && grep -q "iapIn" "$E" && grep -q "Evt;->source" "$E" && grep -q "Evt;->restart" "$E" && ! grep -q "Timer\|postDelayed" "$E"'
check "0.3.2 Evt.java: plain words only (letters, digits, dash), one line per event, never throws, no route data" \
    eval 'E=$P/src/tbt/com/jmk/hud/Evt.java; grep -q "A-Za-z0-9-" "$E" && [ "$(grep -c "Log.i(TAG" "$E")" -ge 2 ] && [ "$(grep -c "catch (Throwable t)" "$E")" -ge 2 ]'
# ---------------------------------------------------------------- 0.3.3: the CarPlay lane message gets through libiap2session and is decoded (carplay-lanes-iap2 recipe, rawlanes.sh)
for f in src/tbt/rawlanes.py src/tbt/rawlanes.sh src/tbt/com/jmk/hud/RawLanes.java src/tbt/stubs/com/tcc/iap2/Iap2NotiMsg.java; do
    check "0.3.3 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.3.3 rawlanes.py: AGPL-3.0 header; stops with status 1 on an empty tree and when the edit is there already (nothing written); applyLanes and laneOne are each found exactly once" \
    eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-gp.XXXXXX"); python3 -I "$P/src/tbt/rawlanes.py" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; grep -q "AGPL-3.0" "$P/src/tbt/rawlanes.py" && grep -q "already" "$P/src/tbt/rawlanes.py" && grep -q "(want 1)" "$P/src/tbt/rawlanes.py" && [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.3.3 RawLanes.java: the attribution (hmg-seogaemo fbaacf7, AGPL-3.0) is in the header; every entry is inside try / catch Throwable; the log line starts with 'cp lanes: raw n='" \
    eval 'R=$P/src/tbt/com/jmk/hud/RawLanes.java; grep -q "seogaemo/hmg-seogaemo" "$R" && grep -q "fbaacf7" "$R" && grep -q "AGPL-3.0" "$R" && [ "$(grep -c "catch (Throwable t)" "$R")" -ge 2 ] && grep -q "cp lanes: raw n=" "$R"'
check "0.3.3 the lane recipe: gated on the stock libiap2session fc7cb675 (result 4ce639fe), one verify per edited place, no other file" \
    eval 'R=$PKG/recipes/carplay-lanes-iap2.recipe; grep -q "^file /system/lib/libiap2session.so" "$R" && [ "$(grep -c "^verify " "$R")" = 6 ] && [ "$(grep -c "^patch " "$R")" = 7 ] && grep -q "^carplay-lanes-iap2 fc7cb675b46a44bd893a1edc054c5e71 4ce639fea732b1ec052407d0b5548c42$" "$PKG/recipes/gates"'
check "0.3.3 the bridge DiPO deltas end at $FIN_DIPO (apk $FIN_DIPO_APK in neev_kr); the 0.2.6 bridge result stays in known" \
    eval '( for o in kr kra krb kre krg kri krk krp krt; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ] || exit 1; done; grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^HKMC_DiPO.dex $FIN_DIPO\$" "$PKG/patches/known" && grep -q "^HKMC_DiPO.dex $P26_DIPO\$" "$PKG/patches/known" )'
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    KT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-keep.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$KT" $(find "$here/keep/stub" -name '*.java') $(find "$P/src/callout/jmkhud/link" -name '*.java' | grep -v '/android/') "$P/src/tbt/com/jmk/hud/Keep.java" "$P/src/tbt/com/jmk/hud/EndLog.java" "$P/src/tbt/com/jmk/hud/Evt.java" "$here/keep/KeepTest.java" "$here/keep/EndLogTest.java" "$here/keep/EvtTest.java" 2>/dev/null; then
        for sc in none late latekeep latestale again againdrop gate separate restart restartkeep restartnone keep drop refresh refreshrecheck norefresh silence recheck busy notes; do
            out=$(java -cp "$KT" com.jmk.hud.KeepTest $sc 2>/dev/null | tail -1)
            check "0.3.2 Keep on the JVM, $sc: $out" eval '[ "$out" = "keep: $sc passed" ]'
        done
        out=$(java -cp "$KT" com.jmk.hud.EndLogTest 2>/dev/null | tail -1)
        check "0.3.2 EndLog counts every blank (Evt line: why / proj / trig / seq / pid) on the JVM: $out" eval '[ "$out" = "endlog: passed" ]'
        out=$(java -cp "$KT" com.jmk.hud.EvtTest 2>/dev/null | tail -1)
        check "0.3.2 Evt on the JVM (lane count, source token, guarded restart, plain words): $out" eval '[ "$out" = "evt: passed" ]'
    else
        check "0.2.5 Keep on the JVM: the sources compile" false
    fi
        RL=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-rawlanes.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$RL" $(find "$here/rawlanes/stub" -name '*.java') "$P/src/tbt/com/jmk/hud/RawLanes.java" "$P/src/tbt/com/jmk/hud/Evt.java" "$here/rawlanes/RawLanesTest.java" 2>/dev/null; then
        out=$(java -cp "$RL" com.jmk.hud.RawLanesTest 2>/dev/null | tail -1)
        check "0.3.3 RawLanes on the JVM (one lane, several, repeated angles, empty, truncated, unknown id, bad lengths): $out" eval '[ "$out" = "rawlanes: passed" ]'
    else
        check "0.3.3 RawLanes on the JVM: the sources compile" false
    fi
    rm -rf "$RL"
    rm -rf "$KT"
else
    echo "(no javac / java on this Mac: the 0.2.5 Keep JVM checks skipped)"
fi
# ---------------------------------------------------------------- 0.2.6: wireless CarPlay keeps the phone's Bluetooth connected (btkeep.sh)
for f in src/tbt/btkeep.py src/tbt/btkeep.sh src/tbt/com/jmk/hud/BtKeep.java; do
    check "0.2.6 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
check "0.2.6 btkeep.py: AGPL-3.0 header; stops with status 1 on an empty tree and when the edit is there already (nothing written)" \
    eval '( et=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-gp.XXXXXX"); python3 -I "$P/src/tbt/btkeep.py" "$et" >/dev/null 2>&1; erc=$?; enf=$(find "$et" -type f | wc -l | tr -d " "); rm -rf "$et"; grep -q "AGPL-3.0" "$P/src/tbt/btkeep.py" && grep -q "already" "$P/src/tbt/btkeep.py" && [ $erc -eq 1 ] && [ "$enf" = 0 ] )'
check "0.2.6 BtKeep.java: the approved sentence is in its header, letter for letter; the source of the rule (Danpung cp_keepbt, AGPL-3.0) is named; every entry is inside try / catch Throwable" \
    eval 'K=$P/src/tbt/com/jmk/hud/BtKeep.java; grep -qF -- "Wireless CarPlay keeps the phone" "$K" && grep -qF -- "s Bluetooth connected." "$K" && grep -q "Danpung 0.8.0-r6c, AGPL-3.0" "$K" && [ "$(grep -c "catch (Throwable t)" "$K")" -ge 3 ]'
check "0.2.6 BtKeep.java: no time rule (no clock, no timer, no sleep); the switch is persist.leafia.cp.keepbt, off only for 0" \
    eval 'K=$P/src/tbt/com/jmk/hud/BtKeep.java; ! grep -q "nanoTime\|currentTimeMillis\|elapsedRealtime\|Timer\|sleep\|postDelayed" "$K" && grep -q "persist.leafia.cp.keepbt" "$K" && grep -q "!\"0\".equals(v)" "$K"'
check "0.2.6 the cp_keepbt knob: the bridge profiles list it (neev_kr kr kra krb kre krg kri krk krp krt), the turn-by-turn-only ones do not (krc krd krm krq krv); common.sh maps it to persist.leafia.cp.keepbt (0 = off, anything else 1) and clears it at uninstall" \
    eval '( for o in kr kra krb kre krg kri krk krp krt; do grep -qx "log lane_dist cp_lanes cp_keepbt" "$PKG/patches/bycode/$o/knobs" || exit 1; done; grep -qx "log lane_dist cp_lanes cp_keepbt" "$PKG/patches/neev_kr/knobs" || exit 1; for o in krc krd krm krq krv; do grep -qx "log lane_dist cp_lanes" "$PKG/patches/bycode/$o/knobs" || exit 1; done; grep -q "cp_keepbt) echo persist.leafia.cp.keepbt" "$PKG/scripts/common.sh" && grep -q "cp_keepbt) case \"\$2\" in 0) echo 0 ;; \*) echo 1 ;; esac ;;" "$PKG/scripts/common.sh" && grep -q "^LEAFIA_PROPS=.*persist.leafia.cp.keepbt" "$PKG/scripts/common.sh" )'
check "0.2.6 the bridge DiPO deltas end at $FIN_DIPO (apk $FIN_DIPO_APK in neev_kr); the turn-by-turn-only ones stay; the 0.2.5 bridge result stays in known" \
    eval '( for o in kr kra krb kre krg kri krk krp krt; do [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $FIN_DIPO ] || exit 1; done; grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $FIN_DIPO_APK$" "$PKG/patches/neev_kr/manifest" || exit 1; for kv in HKMC_DiPO.dex:$FIN_DIPO HKMC_DiPO.apk:$FIN_DIPO_APK HKMC_DiPO.dex:$P25_DIPO HKMC_DiPO.apk:$P25_DIPO_APK; do grep -qx "${kv%%:*} ${kv#*:}" "$PKG/patches/known" || exit 1; done )'
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    BK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-btkeep.XXXXXX")
    if javac -source 7 -target 7 -Xlint:-options -d "$BK" $(find "$here/btkeep/stub" -name '*.java') "$P/src/tbt/com/jmk/hud/BtKeep.java" "$here/btkeep/BtKeepTest.java" 2>/dev/null; then
        for sc in wireless off wired ended log; do
            out=$(java -cp "$BK" com.jmk.hud.BtKeepTest $sc 2>/dev/null | tail -1)
            check "0.2.6 BtKeep on the JVM, $sc: $out" eval '[ "$out" = "btkeep: $sc passed" ]'
        done
        BK2=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-btkeep.XXXXXX"); cp -R "$BK/." "$BK2/"; rm -f "$BK2/com/ev6/cpwl/Bridge.class"
        out=$(java -cp "$BK2" com.jmk.hud.BtKeepTest noflags 2>/dev/null | tail -1)
        check "0.2.6 BtKeep on the JVM, the bridge class cannot be read (stock code runs): $out" eval '[ "$out" = "btkeep: noflags passed" ]'
        rm -f "$BK2/android/os/SystemProperties.class"; cp "$BK/com/ev6/cpwl/Bridge.class" "$BK2/com/ev6/cpwl/Bridge.class" 2>/dev/null
        out=$(java -cp "$BK2" com.jmk.hud.BtKeepTest noprop 2>/dev/null | tail -1)
        check "0.2.6 BtKeep on the JVM, the system properties cannot be read (stock code runs): $out" eval '[ "$out" = "btkeep: noprop passed" ]'
        rm -rf "$BK2"
    else
        check "0.2.6 BtKeep on the JVM: the sources compile" false
    fi
    rm -rf "$BK"
fi
hin 22
hin 23
# ---------------------------------------------------------------- 4. zips
T=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-zip.XXXXXX")
trap 'rm -rf "$T"' EXIT
for variant in "" "--sets neev_kr"; do
    a=$(cd "$P" && JMK_BUILT_DATE=2026-11-17 python3 build_nemesis_package.py $variant | grep '^md5' )
    b=$(cd "$P" && JMK_BUILT_DATE=2026-11-17 python3 build_nemesis_package.py $variant | grep '^md5' )
    check "zip ${variant:-full}: two builds give the same bytes ($a)" [ "$a" = "$b" ]
done
V=$(sed -n 's/^package-version=//p' "$PKG/NEMESIS.data")
for z in "$P/dist/jmk-autoplay-hud-$V.zip" "$P/dist/jmk-autoplay-hud-$V-kr.zip"; do
    list=$(unzip -Z1 "$z")
    for need in LICENSE NOTICE.md README.md LICENSES/GPL-3.0.txt NEMESIS.data tools/lpatch scripts/common.sh svc/hud.sh recipes/carplay-core-frames-ef49c09b.recipe recipes/gates; do
        check "${z##*/}: has $need" eval 'echo "$list" | grep -qx "$need"'
    done
    check "${z##*/}: no dex, jar or apk but tools/codesum.jar (nothing compiled or obfuscated of ours without its source)" eval '! echo "$list" | grep -vx "tools/codesum.jar" | grep -qE "\.(dex|jar|apk)$"'
    check "${z##*/}: tools/codesum.jar's source and build script inside" eval 'echo "$list" | grep -qx src/jmkhud/CodeSum.java && echo "$list" | grep -qx src/build-codesum.sh'
    check "${z##*/}: scripts and lpatch executable" eval '[ -z "$(unzip -Z "$z" | grep -E "(\.sh|tools/lpatch)$" | grep -vE "^[-?]rwxr-xr-x")" ]'
    rm -rf "$T/x"; mkdir "$T/x"; unzip -q "$z" -d "$T/x"
    for f in $scripts; do check "${z##*/}: ${f#./} as in package/" cmp -s "$PKG/$f" "$T/x/$f"; done
done
check "kr zip: only the neev_kr set (and the cars list and our earlier results)" eval '[ "$(unzip -Z1 "$P/dist/jmk-autoplay-hud-$V-kr.zip" | grep "^patches/" | cut -d/ -f2 | sort -u | tr "\n" " ")" = "cars known neev_kr " ]'
for z in "$P/dist/jmk-autoplay-hud-$V.zip" "$P/dist/jmk-autoplay-hud-$V-kr.zip"; do
    check "0.1.17 ${z##*/}: patches/known (= package/) and src/mkknown.py inside" eval 'unzip -p "$z" patches/known | cmp -s - "$PKG/patches/known" && unzip -Z1 "$z" | grep -qx src/mkknown.py'
done
check "full zip: every set" eval '[ "$(unzip -Z1 "$P/dist/jmk-autoplay-hud-$V.zip" | grep "^patches/.*/" | cut -d/ -f2 | sort -u | tr "\n" " ")" = "bycode common dl3hev ev6 ev6_ca neev neev23_260903 neev_ca neev_kr nq5 " ]'
# a release (published, open: not obfuscated) is the full test zip itself, byte for byte
for r in "$P"/dist/release/*.zip; do
    [ -e "$r" ] || continue
    unzip -Z1 "$r" | grep -qx migrate.meta && continue     # the LivePatch release (release.sh): judged by lp-ci, the same bytes as lp/build_lp_package.py's test build (lp/test/build-test.sh)
    check "release ${r##*/} = the full build" cmp -s "$r" "$P/dist/${r##*/}"
done

# ---------------------------------------------------------------- 5. closed packages stay clean
leak=$(grep -rlE 'tools/lpatch|LEAFIA_OTHER_PROPS|prefill_dalvik|wipe_dalvik|\.jmkhud|knob_props|check_recipes|apply_recipe|persist\.leafia\.' "$REPO/apps" --include='*.sh' --include='*.java' --include='*.py' --exclude-dir='.venv*' --exclude-dir=site-packages --exclude-dir=node_modules 2>/dev/null | grep -v '/apps/jmk-autoplay-hud/')
check "no code of this package in the other apps/ packages" [ -z "$leak" ]
[ -n "$leak" ] && echo "$leak" | while IFS= read -r l; do echo "      $l"; done

echo
if [ $n_fail -eq 0 ]; then echo "all $n_ok passed"; exit 0; fi
echo "$n_fail FAILED, $n_ok passed"; exit 1

