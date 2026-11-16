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
check "version: NEMESIS.data package-version 0.1.1" grep -q '^package-version=0.1.1$' "$PKG/NEMESIS.data"
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
    check "${z##*/}: no dex, jar or apk (nothing compiled or obfuscated of ours)" eval '! echo "$list" | grep -qE "\.(dex|jar|apk)$"'
    check "${z##*/}: scripts and lpatch executable" eval '[ -z "$(unzip -Z "$z" | grep -E "(\.sh|tools/lpatch)$" | grep -vE "^[-?]rwxr-xr-x")" ]'
    rm -rf "$T/x"; mkdir "$T/x"; unzip -q "$z" -d "$T/x"
    for f in $scripts; do check "${z##*/}: ${f#./} as in package/" cmp -s "$PKG/$f" "$T/x/$f"; done
done
check "kr zip: only the neev_kr set" eval '[ "$(unzip -Z1 "$P/dist/jmk-autoplay-hud-$V-kr.zip" | grep "^patches/" | cut -d/ -f2 | sort -u | tr "\n" " ")" = "cars neev_kr " ]'
check "full zip: every set" eval '[ "$(unzip -Z1 "$P/dist/jmk-autoplay-hud-$V.zip" | grep "^patches/.*/" | cut -d/ -f2 | sort -u | tr "\n" " ")" = "common dl3hev ev6 ev6_ca neev neev_ca neev_kr " ]'
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
