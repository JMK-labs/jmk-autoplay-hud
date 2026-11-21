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
        case "$part" in ''|'#'*) continue ;; esac
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
# DiPO / Iap2 kr's bridge builds (private/hud-port/groupB-bridge-REPORT.md)
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
# DPPB5BHV); its delta left the package (a copy is held in private/hud-port/ev6kr/held)
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
# ported onto it, private/hud-port/neev-v037-REPORT.md), keyed to V037's codes; the library line is kr's (the same
# library, 48ee793a); no bridge part yet (V037's framework and Broadcom library are needed to check it)
KRV=$PKG/patches/bycode/krv/manifest
check "by code krv: turn-by-turn only, the four apps and the library" [ "$(grep -v '^#' "$KRV" | awk '{print $1":"$3}' | tr '\n' ' ')" = "2_tbt:HKMC_GPM 2_tbt:HKMC_DiPO 2_tbt:Iap2ServerApp 2_tbt:HKMC_Navi_ExSL 2_tbt:libautoreceiver_infobank.so " ]
check "by code krv: no 3_bridge part" eval '! grep -q "^3_bridge " "$KRV"'
for ac in HKMC_GPM:1f29a226774d61a2b4ef899182af28cf:7b0fb9800dc6479d466e06760942ea13 HKMC_DiPO:8d0867878b78347358f136aba85a1287:9794821165c1037e0d15f13bb017289d \
          Iap2ServerApp:661dc714e30802d505c333e33bb7f089:cc198983ce4e3c647eda36e23b292143 HKMC_Navi_ExSL:12a34cb11c9325f9a4050a86a9699469:2e215e95d84eb0906095cf4a5e4601ff; do
    a=${ac%%:*}; c=${ac#*:}; w=${c#*:}; c=${c%%:*}
    check "by code krv: $a is V037's code ($c) -> its own build ($w)" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$KRV")" = "$c bycode/krv/$a.tbt.lpd $w" ]
    for o in kr kra krb kre krg kri krm krp krt us; do
        check "by code krv: $a's code is no other profile's ($o)" eval '! grep -q " $a $c " "$PKG/patches/bycode/$o/manifest"'
    done
    check "by code krv: $a's build is not kr's (V037's own stock code under the patch)" [ "$w" != "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
check "by code krv: the library line is kr's" [ "$(grep '^2_tbt file ' "$KRV")" = "$(grep '^2_tbt file ' "$PKG/patches/bycode/kr/manifest")" ]
check "by code krv: the knobs are kr's" cmp -s "$PKG/patches/bycode/krv/knobs" "$PKG/patches/bycode/kr/knobs"
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
# (private/hud-port/v035-REPORT.md); no library line (another build of the library); no bridge part. krc: Carnival KA4
# and Tucson Hybrid NX4HEV (the same code), its Iap2ServerApp V037's code (krv's line); krd: K5 Hybrid DL3HEV (krc's
# code with other names and framework, so its GPM result is krc's and its Iap2ServerApp result krv's)
KRC=$PKG/patches/bycode/krc/manifest; KRD=$PKG/patches/bycode/krd/manifest
for pv in krc:"$KRC" krd:"$KRD"; do
    p=${pv%%:*}; M=${pv#*:}
    check "by code $p: turn-by-turn only, the four apps, no library line" [ "$(grep -v '^#' "$M" | awk '{print $1":"$2":"$3}' | tr '\n' ' ')" = "2_tbt:app:HKMC_GPM 2_tbt:app:HKMC_DiPO 2_tbt:app:Iap2ServerApp 2_tbt:app:HKMC_Navi_ExSL " ]
    check "by code $p: no 3_bridge part" eval '! grep -q "^3_bridge " "$M"'
    check "by code $p: the knobs are kr's" cmp -s "$PKG/patches/bycode/$p/knobs" "$PKG/patches/bycode/kr/knobs"
done
for ac in krc:HKMC_GPM:4cf385316c37ddc4d5c28ba69d99caee:965c4bfa035f24caeba188d9450a7e35 krc:HKMC_DiPO:84f17a7a755b5a3022a139526ba452bd:e9b17e59a3231ffdc6b683f312957b10 \
          krc:HKMC_Navi_ExSL:ea6e2da50080b288f908962a6c8d5794:1bcc141690b4cab381a4f2a242829f2c \
          krd:HKMC_GPM:d244aba596a361c850311bb0603d1eab:965c4bfa035f24caeba188d9450a7e35 krd:HKMC_DiPO:072ba128b4daf9669dc329cfa168a3ee:be272d864b76d0dd0147c1fa64861164 \
          krd:Iap2ServerApp:9f32383bbf425173727ce6365971fa28:cc198983ce4e3c647eda36e23b292143 krd:HKMC_Navi_ExSL:d43adb26a20f55e5bdfd5e313bb66c9d:cbf5ce775fdd6e61767ea6bff2ea5d64; do
    p=${ac%%:*}; r=${ac#*:}; a=${r%%:*}; r=${r#*:}; c=${r%%:*}; w=${r#*:}
    check "by code $p: $a is V035's code ($c) -> its own delta, result $w" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$PKG/patches/bycode/$p/manifest")" = "$c bycode/$p/$a.tbt.lpd $w" ]
    for o in kr kra krb kre krg kri krm krp krt krv us krc krd; do
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
# framework's two string IDs, the library line kr's; no bridge part (private/hud-port/mq4-v037-REPORT.md)
KRM=$PKG/patches/bycode/krm/manifest
check "by code krm: turn-by-turn only, the four apps and the library" [ "$(grep -v '^#' "$KRM" | awk '{print $1":"$3}' | tr '\n' ' ')" = "2_tbt:HKMC_GPM 2_tbt:HKMC_DiPO 2_tbt:Iap2ServerApp 2_tbt:HKMC_Navi_ExSL 2_tbt:libautoreceiver_infobank.so " ]
check "by code krm: no 3_bridge part" eval '! grep -q "^3_bridge " "$KRM"'
for ac in HKMC_GPM:a79f26f3689641f9274c01cdafab52d1:7b0fb9800dc6479d466e06760942ea13 HKMC_DiPO:803a1a0e58d0bc5fed3d0e1fa4ee13bd:9794821165c1037e0d15f13bb017289d \
          HKMC_Navi_ExSL:93bca3a2125a1b33c572b20ce6b3a5e1:584218add8cac46fd7fcf1c72d7b20e4; do
    a=${ac%%:*}; c=${ac#*:}; w=${c#*:}; c=${c%%:*}
    check "by code krm: $a is MQ4 V037's code ($c) -> its own delta, result $w" [ "$(awk -v n=$a '$1=="2_tbt" && $3==n {print $4" "$5" "$6}' "$KRM")" = "$c bycode/krm/$a.tbt.lpd $w" ]
    for o in kr kra krb krc krd kre krg kri krp krt krv us; do
        check "by code krm: $a's code is no other profile's ($o)" eval '! grep -q " $a $c " "$PKG/patches/bycode/$o/manifest"'
    done
done
for a in HKMC_GPM HKMC_DiPO; do
    check "by code krm: $a ends at krv's build (the same plain code)" [ "$(want_of "$KRM" 2_tbt $a)" = "$(want_of "$KRV" 2_tbt $a)" ]
done
for o in kr kra krb krc krd kre krg kri krp krt krv us; do
    check "by code krm: Navi's build is not $o's (krv's with this framework's two string IDs)" [ "$(want_of "$KRM" 2_tbt HKMC_Navi_ExSL)" != "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_Navi_ExSL)" ]
done
check "by code krm: Iap2ServerApp is krd's code (9f32383b): krd's line, word for word" [ "$(grep '^2_tbt app Iap2ServerApp ' "$KRM")" = "$(grep '^2_tbt app Iap2ServerApp ' "$KRD")" ]
check "by code krm: the library line is kr's (the Ioniq 5's library, 48ee793a)" [ "$(grep '^2_tbt file ' "$KRM")" = "$(grep '^2_tbt file ' "$PKG/patches/bycode/kr/manifest")" ]
check "by code krm: the knobs are kr's" cmp -s "$PKG/patches/bycode/krm/knobs" "$PKG/patches/bycode/kr/knobs"
MQ4="a79f26f3689641f9274c01cdafab52d1 803a1a0e58d0bc5fed3d0e1fa4ee13bd 9f32383bbf425173727ce6365971fa28 93bca3a2125a1b33c572b20ce6b3a5e1"
check "by code choice (0.1.18): a Sorento MQ4 V037 car (DWW5FPAD's codes) gets krm, turn-by-turn only" [ "$(sel_of $MQ4 8d1a93d8b23ef49abd2ccfeb8449e97f $LIB_KR)" = "krm 2_tbt" ]
check "by code choice (0.1.18): a Grandeur IGPE V037 car (OB3JWHQB's codes, its own PhoneProjection) gets krm" [ "$(sel_of $MQ4 db3b717a98318abff7c7a0119644351d $LIB_KR)" = "krm 2_tbt" ]
check "by code choice (0.1.18): MQ4 V037's code with another library fits nothing (the part is all or nothing)" [ "$(sel_of $MQ4 8d1a93d8b23ef49abd2ccfeb8449e97f 0123456789abcdef0123456789abcdef)" = none ]
check "by code choice (0.1.18): MQ4 V037 with krv's GPM code fits nothing (krv's other codes are not MQ4's)" [ "$(sel_of 1f29a226774d61a2b4ef899182af28cf 803a1a0e58d0bc5fed3d0e1fa4ee13bd 9f32383bbf425173727ce6365971fa28 93bca3a2125a1b33c572b20ce6b3a5e1 8d1a93d8b23ef49abd2ccfeb8449e97f $LIB_KR)" = none ]
# 0.1.17: the dl3hev set (Leafia's original build, unchanged since projection.tbt) is superseded: the by-code profiles
# first. Its cars (DL3, DL322, DL3HEV22, MQ422HEV, MQ4HEV, YGPE, CKPE, DEPEHEV V039.001.260902, all with exactly its stock
# files) run group B's GPM / DiPO / Iap2ServerApp / Navi code (every Leafia dl3hev delta rebuilds its target md5 from it:
# private/hud-port/dl3hev-v039/tools/probe_src.py) and the Ioniq 5's library: krb's turn-by-turn part. Their
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
NEW_GPM=d2538947dcd6a8af532e0fb2baf7be81; NEW_DIPO=913848d61d675beb066e03f119a4cf6e; OLD_DIPO=1452d2d8c9670bb8f44c39569d3220f5
DIPO_013=d760fe5bdb6e00e7afd18fef2155dd1c; NEW_DIPO_APK=e4cc7bb2e6e5d532aeb19620f2860486
GPM_018=b02ada70f0de90a9e09d364a64559074; DIPO_018=56d9ff800ddc5a750fa2be6d247deb5d; DIPO_APK_018=ad5a3139510fe65a87a0d71f9cd82aff
NEW_DIPOT=6dfde547549483ca65e822f5e992e275; NEW_GPM_APK=00613075311c59881d379f384ed77327; NEW_DIPOT_APK=956eefb7194ab7c3f3294c14a6150d38
for o in kr kra krb kre krg kri krp krt; do
    check "0.1.19 $o: GPM ends at the near-turn + TBT clear build $NEW_GPM (0.1.18: $GPM_018)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $NEW_GPM ]
    check "0.1.19 $o: DiPO turn-by-turn build = 0.1.18's ffe9b558 + TBT clear ($NEW_DIPOT)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_DiPO)" = $NEW_DIPOT ]
    check "0.1.19 $o: DiPO bridge ends at the near-turn + wireless iAP2 + CarPlay-channel resume + TBT clear build $NEW_DIPO (not 0.1.18's $DIPO_018, 0.1.13's $DIPO_013, 0.1.11's $OLD_DIPO)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $NEW_DIPO ]
done
check "0.1.19 neev_kr: GPM delta ends at the near-turn + TBT clear build, DiPO bridge delta at the near-turn + wireless iAP2 + CarPlay-channel resume + TBT clear build" eval '[ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_GPM.tbt.lpd")" = $NEW_GPM ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd")" = $NEW_DIPO ]'
check "0.1.19 neev_kr: result apks (lpatch zipadd of those into the stock apks: GPM $NEW_GPM_APK, DiPO $NEW_DIPO_APK; 0.1.18's 8b13805f / ad5a3139, 0.1.13's DiPO 13633ac6)" eval 'grep -q "^2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd $NEW_GPM_APK$" "$PKG/patches/neev_kr/manifest" && grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $NEW_DIPO_APK$" "$PKG/patches/neev_kr/manifest"'
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
check "0.1.18 build.sh: applies cp-iap-resume.diff after wireless-iap2.diff, to the tree with com/ev6/cpwl/Bridge.smali, documents 86ce5550 -> $NEW_DIPO" \
    eval 'grep -q "if \[ -f \"\$work/tree/com/ev6/cpwl/Bridge.smali\" \]; then" "$P/src/tbt/build.sh" && [ "$(grep -n "wireless-iap2.diff\"$" "$P/src/tbt/build.sh" | cut -d: -f1)" -lt "$(grep -n "cp-iap-resume.diff\"$" "$P/src/tbt/build.sh" | cut -d: -f1)" ] && grep -q "86ce5550bedb50e9ce1d07b81b3273a9 -> $NEW_DIPO" "$P/src/tbt/build.sh"'
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
    check "0.1.18 $lp/HKMC_DiPO.bridge.lpd: ends at $NEW_DIPO and carries the new class (Lcom/ev6/cpwl/CpIapResume;)" eval '[ "$(lpd_dst "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd")" = $NEW_DIPO ] && lpd_extra_has "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd" "Lcom/ev6/cpwl/CpIapResume;"'
done
for lp in "$PKG"/patches/*/HKMC_DiPO.tbt.lpd "$PKG"/patches/bycode/*/HKMC_DiPO.tbt*.lpd "$PKG"/patches/bycode/us/HKMC_DiPO.bridge.*.lpd \
          "$PKG"/patches/neev*/HKMC_DiPO.bridge.lpd "$PKG"/patches/ev6/HKMC_DiPO.bridge.lpd "$PKG"/patches/nq5/HKMC_DiPO.bridge.lpd "$PKG"/patches/dl3hev/HKMC_DiPO.bridge.lpd; do
    [ "$lp" = "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd" ] && continue
    check "0.1.18 ${lp#$PKG/patches/}: no CpIapResume (not a Korean bridge build)" eval 'lpd_extra_has "$lp" "Lcom/ev6/cpwl/CpIapResume;"; [ $? -eq 1 ]'
done
# profiles with no bridge part (their DiPO bridge is held or there is none): no 3_bridge line, turn-by-turn DiPO unchanged
for pd in krc:e9b17e59a3231ffdc6b683f312957b10 krd:be272d864b76d0dd0147c1fa64861164 krm:9794821165c1037e0d15f13bb017289d krv:9794821165c1037e0d15f13bb017289d; do
    p=${pd%%:*}; w=${pd#*:}
    check "0.1.18 $p: no 3_bridge part, no DiPO bridge delta (held), its DiPO turn-by-turn build the 0.1.19 one ($w)" eval '! grep -q "^3_bridge " "$PKG/patches/bycode/$p/manifest" && ! ls "$PKG/patches/bycode/$p/" | grep -q "bridge" && [ "$(want_of "$PKG/patches/bycode/$p/manifest" 2_tbt HKMC_DiPO)" = $w ]'
done
check "0.1.19 neev_kr: DiPO turn-by-turn build = 0.1.18's 5bc5707c + TBT clear ($NEW_DIPOT_APK)" grep -q "^2_tbt app HKMC_DiPO neev_kr/HKMC_DiPO.tbt.lpd $NEW_DIPOT_APK$" "$PKG/patches/neev_kr/manifest"
check "0.1.18 / 0.1.19 known: 0.1.13's and 0.1.18's neev_kr DiPO apks (13633ac6, ad5a3139) and this one ($NEW_DIPO_APK) are all ours" eval 'grep -qx "HKMC_DiPO.apk 13633ac624e850cfad2aa80ddf0be445" "$PKG/patches/known" && grep -qx "HKMC_DiPO.apk $DIPO_APK_018" "$PKG/patches/known" && grep -qx "HKMC_DiPO.apk $NEW_DIPO_APK" "$PKG/patches/known"'
check "0.1.19 known: 0.1.18's neev_kr GPM apk (8b13805f) and this one ($NEW_GPM_APK) are both ours" eval 'grep -qx "HKMC_GPM.apk 8b13805f77cd8bb35691fb8b43a8bb99" "$PKG/patches/known" && grep -qx "HKMC_GPM.apk $NEW_GPM_APK" "$PKG/patches/known"'
# with the build inputs on this Mac (private/hud-port): build.sh gives the pinned results, and each package delta
# rebuilds the new DiPO bridge from a real stock copy of its code (skipped without them)
B010=$REPO/private/hud-port/dipo-wireless-iap2
if [ -f "$B010/dipo-0.1.10.dex" ] && [ -f "$B010/gpm-0.1.10.dex" ] && command -v javac >/dev/null 2>&1 && [ -x "$B010/lpatch-host" ]; then
    BT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-tbt.XXXXXX")
    check "0.1.19 build.sh: 0.1.10's DiPO 86ce5550 -> $NEW_DIPO" eval '[ "$(bash "$P/src/tbt/build.sh" "$B010/dipo-0.1.10.dex" "$BT/dipo.dex" 2>/dev/null | tail -1)" = $NEW_DIPO ]'
    check "0.1.19 build.sh: 0.1.10's GPM 990ef4c3 -> $NEW_GPM (no bridge class: no cp-iap-resume.diff)" eval '[ "$(bash "$P/src/tbt/build.sh" "$B010/gpm-0.1.10.dex" "$BT/gpm.dex" 2>/dev/null | tail -1)" = $NEW_GPM ]'
    check "0.1.18 the new DiPO bridge has CpIapResume and its log line" eval 'LC_ALL=C grep -qa "Lcom/ev6/cpwl/CpIapResume;" "$BT/dipo.dex" && LC_ALL=C grep -qa "CarPlay-channel iAP2 session ready, setStartiAP2Service again" "$BT/dipo.dex"'
    H=$REPO/private/hud-port; BL=$H/uploads/blobs
    for pair in bycode/kr:$REPO/private/stock-neev-kr-260902/stock3/app/HKMC_DiPO.odex bycode/kr:$H/ceev-ikfl/stock-ikfl/HKMC_DiPO.odex \
                bycode/krb:$H/groupB-bridge/stock-b/HKMC_DiPO.odex bycode/krb:$BL/950b5575603e50aea9894b3568e80e21b3a354a6c812c3991010ab3e0cb9fe90 \
                bycode/kre:$H/ev6kr/stock/HKMC_DiPO.odex bycode/kre:$BL/caa5def8ab938f06d2ed212d061ff8758879da07cdd6e14a08e2930bdecb9291 \
                bycode/krp:$H/cn7pe/HKMC_DiPO.odex bycode/krp:$H/ceev-ikfl/stock-ceev/HKMC_DiPO.odex; do
        lp=${pair%%:*}; s=${pair#*:}
        [ -f "$s" ] || continue
        check "0.1.18 $lp DiPO bridge delta on a real stock copy (${s#$REPO/}) -> $NEW_DIPO (host lpatch)" eval '"$B010/lpatch-host" odexdex "$s" "$BT/code.dex" >/dev/null && "$B010/lpatch-host" delta "$PKG/patches/$lp/HKMC_DiPO.bridge.lpd" "$BT/code.dex" "$BT/out.dex" >/dev/null && [ "$(md5 -q "$BT/out.dex")" = $NEW_DIPO ]'
    done
    S3=$REPO/private/stock-neev-kr-260902/stock3
    if [ -f "$S3/app/HKMC_DiPO.odex" ] && [ -f "$H/stock-HKMC_DiPO.apk" ]; then
        check "0.1.18 neev_kr DiPO bridge delta on the stock odex -> $NEW_DIPO, zipadd into the stock apk -> $NEW_DIPO_APK (host lpatch)" eval '"$B010/lpatch-host" delta "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd" "$S3/app/HKMC_DiPO.odex" "$BT/nk.dex" >/dev/null && [ "$(md5 -q "$BT/nk.dex")" = $NEW_DIPO ] && "$B010/lpatch-host" zipadd "$H/stock-HKMC_DiPO.apk" "$BT/nk.dex" "$BT/nk.apk" >/dev/null && [ "$(md5 -q "$BT/nk.apk")" = $NEW_DIPO_APK ]'
    fi
    rm -rf "$BT"
else
    echo "(the 0.1.10 build inputs or the host lpatch are not on this Mac: the 0.1.18 rebuild checks skipped)"
fi
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
# 0.1.19: the turn-by-turn release at the end of the projection session and the com.jmk.hud.TBT_CLEAR receiver
# (src/tbt/tbt-clear.py on the smali tree + com/jmk/hud/TbtClear.java; src/tbt/clear.sh makes each 0.1.19 GPM / DiPO
# result from its 0.1.18 result): every GPM / DiPO result that carries our turn-by-turn patches changes, nothing else
TC=$P/src/tbt/tbt-clear.py; TJ=$P/src/tbt/com/jmk/hud/TbtClear.java
R019="d2538947dcd6a8af532e0fb2baf7be81 965c4bfa035f24caeba188d9450a7e35 7b0fb9800dc6479d466e06760942ea13 913848d61d675beb066e03f119a4cf6e 6dfde547549483ca65e822f5e992e275 e9b17e59a3231ffdc6b683f312957b10 be272d864b76d0dd0147c1fa64861164 9794821165c1037e0d15f13bb017289d"
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
# with the 0.1.18 results on this Mac: clear.sh gives each pinned 0.1.19 result; the host lpatch rebuilds it from every
# real stock copy (private/hud-port/tbt-clear: mk_019.py made the deltas, verify_c.sh checks them)
H19=$REPO/private/hud-port
if command -v javac >/dev/null 2>&1 && [ -f "$H19/nowplaying-updates/build/dipo-0.1.18-56d9ff80.dex" ] && [ -x "$H19/dipo-wireless-iap2/lpatch-host" ]; then
    CT=$(mktemp -d "${TMPDIR:-/tmp}/jmk-hud-clear.XXXXXX")
    for pr in dipo-wireless-iap2/gpm-0.1.13-b02ada70.dex:d2538947dcd6a8af532e0fb2baf7be81 v035/dl3/build/HKMC_GPM.2_tbt/result.dex:965c4bfa035f24caeba188d9450a7e35 \
              mq4-v037/build/HKMC_GPM.2_tbt/result.dex:7b0fb9800dc6479d466e06760942ea13 nowplaying-updates/build/dipo-0.1.18-56d9ff80.dex:913848d61d675beb066e03f119a4cf6e \
              cn7pe/build/kr-dipo-tbt.dex:6dfde547549483ca65e822f5e992e275 v035/ka4/build/HKMC_DiPO.2_tbt/result.dex:e9b17e59a3231ffdc6b683f312957b10 \
              v035/dl3/build/HKMC_DiPO.2_tbt/result.dex:be272d864b76d0dd0147c1fa64861164 mq4-v037/build/HKMC_DiPO.2_tbt/result.dex:9794821165c1037e0d15f13bb017289d; do
        src=$H19/${pr%%:*}; w=${pr#*:}
        [ -f "$src" ] || continue
        check "0.1.19 clear.sh: 0.1.18's $(md5 -q "$src" | cut -c1-8) (${pr%%:*}) -> $w" eval '[ "$(bash "$P/src/tbt/clear.sh" "$src" "$CT/x.dex" 2>/dev/null | tail -1)" = $w ] && LC_ALL=C grep -qa "com.jmk.hud.TBT_CLEAR" "$CT/x.dex" && LC_ALL=C grep -qa "Lcom/jmk/hud/TbtClear;" "$CT/x.dex"'
    done
    rm -rf "$CT"
    if [ -f "$H19/tbt-clear/mk_019.log" ]; then
        vc=$(bash "$H19/tbt-clear/tools/verify_c.sh" 2>&1 | tail -1)
        check "0.1.19 every GPM / DiPO delta on every real stock copy on this Mac (host lpatch, verify_c.sh: $vc)" eval 'case "$vc" in *" ok, 0 failed") true ;; *) false ;; esac'
    fi
else
    echo "(the 0.1.18 results or the host lpatch are not on this Mac: the 0.1.19 rebuild checks skipped)"
fi
check "by code: the profile with the most parts wins (bycode_build tries both parts first)" grep -q 'for want in 2 1' "$PKG/scripts/common.sh"
while read -r pre set name; do
    case "$pre" in ''|'#'*) continue ;; esac
    check "cars: $pre -> $set exists" [ -f "$PKG/patches/$set/manifest" ]
done < "$PKG/patches/cars"
for f in "$PKG"/patches/*/knobs; do
    keys=$(grep -v '^#' "$f" | tr ' ' '\n' | grep .)
    for k in $keys; do check "knobs ${f#$PKG/}: $k has a switch in common.sh" eval 'case "$k" in log|lane_dist|cp_lanes) true ;; *) false ;; esac'; done
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
        case "$c" in HKMC_GPM|HKMC_DiPO) check "neev_kr result $c is ours (0.1.5 guidance-end fix, 0.1.11 near-turn filter, DiPO 0.1.13 wireless iAP2 and 0.1.18 CarPlay-channel resume, 0.1.19 TBT clear), not Leafia KR's" [ "$fin" != "$e" ]; continue ;; esac
        check "neev_kr result $c = what Leafia KR leaves on the car (final.md5 $f)" [ "$fin" = "$e" ]
    done < <(effective neev_kr)
else
    echo "(Leafia's KR md5 lists not on this Mac: skipped)"
fi
STOCK3="$REPO/private/stock-neev-kr-260902/stock3"
if [ -d "$STOCK3" ]; then
    for f in "$STOCK3"/app/* "$STOCK3"/lib/*; do
        b=${f##*/}; s=$(stock_of neev_kr "$b")
        [ -n "$s" ] && check "neev_kr stock $b = the copy pulled from our car" [ "$(md5 -q "$f")" = "$s" ]
    done
fi
for r in "$PKG"/recipes/*.recipe; do
    check "recipe ${r##*/}: id and file lines" eval 'grep -q "^id " "$r" && grep -q "^file /system/lib/" "$r"'
done
check "lpatch is Leafia 1.0.5's (sha256 b11077ab…)" [ "$(shasum -a 256 "$PKG/tools/lpatch" | cut -d' ' -f1)" = b11077ab6bbba7a2dbed225340d06db46c843a667a3813f894f2927ec61c2bb6 ]
check "libev6aac.so is Leafia's (md5 = CONV_SUM)" [ "$(md5 -q "$PKG/files/libev6aac.so")" = "$(grep -o 'CONV_SUM=[0-9a-f]*' "$PKG/scripts/common.sh" | cut -d= -f2)" ]
check "version: NEMESIS.data package-version 0.1.19" grep -q '^package-version=0.1.19$' "$PKG/NEMESIS.data"
before=$(shasum -a 256 "$PKG/tools/codesum.jar" | cut -d' ' -f1)
if bash "$P/src/build-codesum.sh" >/dev/null 2>&1; then
    check "tools/codesum.jar is the build of src/jmkhud/CodeSum.java (src/build-codesum.sh gives the same bytes)" [ "$(shasum -a 256 "$PKG/tools/codesum.jar" | cut -d' ' -f1)" = "$before" ]
fi
check "NOTICE names tools/codesum.jar with its sha256" grep -q "$before" "$P/NOTICE.md"
check "NEMESIS.data: id, depends, os" eval 'grep -q "^id=jmk-autoplay-hud$" "$PKG/NEMESIS.data" && grep -q "^depends=\"jmk-autoplay\"$" "$PKG/NEMESIS.data" && grep -q "^os=\"\*.KOR.\*\"$" "$PKG/NEMESIS.data"'

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
    for need in LICENSE NOTICE.md README.md LICENSES/GPL-3.0.txt NEMESIS.data tools/lpatch scripts/common.sh svc/hud.sh; do
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
    check "release ${r##*/} = the full build" cmp -s "$r" "$P/dist/${r##*/}"
done

# ---------------------------------------------------------------- 5. closed packages stay clean
leak=$(grep -rlE 'tools/lpatch|LEAFIA_OTHER_PROPS|prefill_dalvik|wipe_dalvik|\.jmkhud|knob_props|check_recipes|apply_recipe|persist\.leafia\.' "$REPO/apps" --include='*.sh' --include='*.java' --include='*.py' --exclude-dir='.venv*' --exclude-dir=site-packages --exclude-dir=node_modules 2>/dev/null | grep -v '/apps/jmk-autoplay-hud/')
check "no code of this package in the other apps/ packages" [ -z "$leak" ]
[ -n "$leak" ] && echo "$leak" | while IFS= read -r l; do echo "      $l"; done

echo
if [ $n_fail -eq 0 ]; then echo "all $n_ok passed"; exit 0; fi
echo "$n_fail FAILED, $n_ok passed"; exit 1
