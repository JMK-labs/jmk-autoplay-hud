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
# and Iap2, PhoneProjection kr's bridge with android:id/topPanel moved, and the library: kr's hook moved to EV6's own
# library addresses (a new result)
KRE=$PKG/patches/bycode/kre/manifest
for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
    check "by code kre: $a ends at kr's turn-by-turn build" [ "$(want_of "$KRE" 2_tbt $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 2_tbt $a)" ]
done
for a in Iap2ServerApp HKMC_DiPO; do
    check "by code kre: $a ends at kr's bridge build" [ "$(want_of "$KRE" 3_bridge $a)" = "$(want_of "$PKG/patches/bycode/kr/manifest" 3_bridge $a)" ]
done
check "by code kre: PhoneProjection is EV6's code -> its own bridge build" [ "$(awk '$1=="3_bridge" && $3=="PhoneProjection" {print $4" "$6}' "$KRE")" = "7e61ce5caa6bdc1ad02563fc084e240a 52816a4c37a512da5a118f101ab5f766" ]
check "by code kre: the library line is EV6's library -> its own result" [ "$(awk '$1=="2_tbt" && $2=="file" {print $4" "$6}' "$KRE")" = "c4fbccdf63f7d823f24010afec43c937 120bab2c81ee6c238e2aab219bf2babe" ]
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
# 0.1.11: the near-turn filter (src/tbt: com.jmk.hud.Near + near-hooks.diff, built by src/tbt/build.sh from the 0.1.10
# results 990ef4c3 / 86ce5550): every Korean profile's GPM and DiPO bridge end at the same two new results, the DiPO
# turn-by-turn build (no near-turn layout in it) is unchanged, and so is the us profile (no Leafia KR code)
NEW_GPM=b02ada70f0de90a9e09d364a64559074; NEW_DIPO=1452d2d8c9670bb8f44c39569d3220f5
for o in kr kra krb kre krg kri krp krt; do
    check "0.1.11 $o: GPM ends at the near-turn build $NEW_GPM" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_GPM)" = $NEW_GPM ]
    check "0.1.11 $o: DiPO turn-by-turn build unchanged (ffe9b558)" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 2_tbt HKMC_DiPO)" = ffe9b558a288cdda39eabd92d4b5fccf ]
    check "0.1.11 $o: DiPO bridge ends at the near-turn build $NEW_DIPO" [ "$(want_of "$PKG/patches/bycode/$o/manifest" 3_bridge HKMC_DiPO)" = $NEW_DIPO ]
done
check "0.1.11 neev_kr: GPM and DiPO bridge deltas end at the near-turn builds" eval '[ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_GPM.tbt.lpd")" = $NEW_GPM ] && [ "$(lpd_dst "$PKG/patches/neev_kr/HKMC_DiPO.bridge.lpd")" = $NEW_DIPO ]'
check "0.1.11 neev_kr: result apks (lpatch zipadd of those into the stock apks)" eval 'grep -q "^2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd 8b13805f77cd8bb35691fb8b43a8bb99$" "$PKG/patches/neev_kr/manifest" && grep -q "^3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd 1ced905ac98063210d93daa536eb9aeb$" "$PKG/patches/neev_kr/manifest"'
check "0.1.11 us: no Leafia KR near-turn code, its results unchanged" eval '[ "$(want_of "$PKG/patches/bycode/us/manifest" 2_tbt HKMC_GPM)" = 6124a666b2ae11883e91de85c19389d2 ] && [ "$(want_of "$PKG/patches/bycode/us/manifest" 3_bridge HKMC_DiPO)" = 5f24681fec4e0ff21f913f3372465524 ]'
for f in src/tbt/com/jmk/hud/Near.java src/tbt/near-hooks.diff src/tbt/build.sh; do
    check "0.1.11 source $f in the package (TOP_FILES)" eval '[ -s "$P/$f" ] && grep -q "$f" "$P/build_nemesis_package.py"'
done
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
        # near-turn filter (src/tbt), so their results are Leafia KR's plus those changes; every other target is still
        # Leafia KR's byte for byte
        case "$c" in HKMC_GPM|HKMC_DiPO) check "neev_kr result $c is ours (0.1.5 guidance-end fix, 0.1.11 near-turn filter), not Leafia KR's" [ "$fin" != "$e" ]; continue ;; esac
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
check "version: NEMESIS.data package-version 0.1.12" grep -q '^package-version=0.1.12$' "$PKG/NEMESIS.data"
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
check "kr zip: only the neev_kr set" eval '[ "$(unzip -Z1 "$P/dist/jmk-autoplay-hud-$V-kr.zip" | grep "^patches/" | cut -d/ -f2 | sort -u | tr "\n" " ")" = "cars neev_kr " ]'
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
