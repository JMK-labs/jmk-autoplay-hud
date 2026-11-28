#!/usr/bin/env bash
# lp/package/scripts/legacy-restore.sh + legacy-verify.sh in a fake car root (JMK_HUD_TEST_ROOT): every record shape the legacy HUD left.
here="$(cd "$(dirname "$0")" && pwd)"
SC="$here/../package/scripts"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lr-test.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok()   { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
q() { md5 -q "$1" 2>/dev/null; }

cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { local l; while IFS= read -r l; do case "$l" in "$1="*) echo "${l#*=}"; return 0 ;; esac; done < "$PROPFILE"; echo; }
pm() {
    echo "pm $*" >> "$JMK_HUD_TEST_ROOT/pm.log"
    case "$1 $2" in "list packages") case " $PM_PKGS " in *" $4 "*) echo "package:$4" ;; esac; return 0 ;; esac
    [ "$1" = disable ] && [ -n "$PM_FAIL" ] && return 1
    return 0
}
app_process() { return 1; }
SH

# a fake car: stock = "S:<name>", ours = "O:<name>"; returns the root in $T
new_car() {
    T=$WORK/car.$1; rm -rf "$T"; mkdir -p "$T/system/app" "$T/system/lib" "$T/system/xbin" "$T/proc" "$T/data/nemesis/jmk-autoplay-hud" "$T/data/nemesis/backups/jmk-autoplay-hud"
    echo "/dev/block/x /system ext4 rw,relatime 0 0" > "$T/proc/mounts"
    printf 'ro.build.fingerprint=FP1\nsys.boot_completed=1\n' > "$WORK/props.$1"; export PROPFILE=$WORK/props.$1
    : > "$T/pm.log"; PM_PKGS="com.google.android.projection.sink com.daudio.app.dipo com.tcc.iap2server com.mnsoft.navi com.daudio.app.phoneprojection"; export PM_PKGS PM_FAIL=
    printf '#!/bin/sh\nsed -i.bak "s/ ro,/ rw,/" "%s/proc/mounts"\n' "$T" > "$T/system/xbin/nemesis"; chmod +x "$T/system/xbin/nemesis"
    echo FP1 > /dev/null
}
mk() { printf '%s\n' "$2" > "$1"; }   # mk <path> <content>
# a patched car: GPM apk+odex and the converter lib are ours; DiPO untouched
patched_car() {
    new_car "$1"
    mk "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"; mk "$T/system/app/HKMC_GPM.odex" "O:gpm.odex"
    mk "$T/system/app/HKMC_DiPO.apk" "S:dipo.apk"
    mk "$T/system/lib/libev6aac.so" "O:conv"
    local B=$T/data/nemesis/backups/jmk-autoplay-hud S=$T/data/nemesis/jmk-autoplay-hud
    mk "$B/HKMC_GPM.apk" "S:gpm.apk"; mk "$B/HKMC_GPM.odex" "S:gpm.odex"
    printf 'HKMC_GPM.apk %s\nHKMC_GPM.odex %s\nHKMC_DiPO.apk %s\n' "$(q "$B/HKMC_GPM.apk")" "$(q "$B/HKMC_GPM.odex")" "$(q "$T/system/app/HKMC_DiPO.apk")" > "$S/stock"
    printf 'HKMC_GPM.apk %s\nHKMC_GPM.odex %s\n' "$(q "$T/system/app/HKMC_GPM.apk")" "$(q "$T/system/app/HKMC_GPM.odex")" > "$S/applied"
    printf 'libev6aac.so %s\n' "$(q "$T/system/lib/libev6aac.so")" > "$S/added"
    echo FP1 > "$S/fingerprint"
    cp "$S/applied" "$T/data/nemesis/jmk-autoplay-hud.made"
}
run() {   # run <mode args...>: output in $OUT, status in $RC (the real script, run by sh)
    OUT=$(JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims PATH=$PATH sh "$SC/legacy-restore.sh" "$@" 2>&1); RC=$?
}
runv() { OUT=$(JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims sh "$SC/legacy-verify.sh" 2>&1); RC=$?; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
hasnt() { has "$1" && return 1; return 0; }
same() { [ "$(cat "$1")" = "$2" ]; }

# 1. no record at all: nothing to do (10), verify 0
new_car t1; run; check "no records: exit 10" test $RC = 10; runv; check "no records: verify 0" test $RC = 0

# 2. a patched car: restore puts it all back
patched_car t2
runv; check "patched: verify says not stock (1)" test $RC = 1
run --check; check "--check exit 1" test $RC = 1
check "--check wrote nothing" same "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"
run
check "restore exit 0" test $RC = 0
check "GPM apk back" same "$T/system/app/HKMC_GPM.apk" "S:gpm.apk"
check "GPM odex back" same "$T/system/app/HKMC_GPM.odex" "S:gpm.odex"
check "DiPO untouched" same "$T/system/app/HKMC_DiPO.apk" "S:dipo.apk"
check "converter removed" test ! -e "$T/system/lib/libev6aac.so"
check "only GPM held, DiPO not" bash -c "grep -q 'pm disable com.google.android.projection.sink' '$T/pm.log' && grep -q 'pm disable com.daudio.app.dipo' '$T/pm.log'"   # DiPO owns libev6aac.so: it changes too
check "navi not held" bash -c "! grep -q 'disable com.mnsoft.navi' '$T/pm.log'"
check "apps started again" bash -c "grep -q 'enable com.google.android.projection.sink' '$T/pm.log'"
check "last line" has "legacy-restore: restored; every file is stock"
runv; check "after: verify 0" test $RC = 0
run; check "second run: nothing to do (10)" test $RC = 10

# 3. backup lost, archive has the copy
patched_car t3
B=$T/data/nemesis/backups/jmk-autoplay-hud; A=$B.stock; mkdir -p "$A"
for f in HKMC_GPM.apk HKMC_GPM.odex; do m=$(q "$B/$f"); cp "$B/$f" "$A/$f.$m"; echo "$f $m FP1" >> "$A/index"; done
rm -f "$B/HKMC_GPM.apk" "$B/HKMC_GPM.odex"
run; check "archive copy used: exit 0" test $RC = 0
check "archive: apk stock" same "$T/system/app/HKMC_GPM.apk" "S:gpm.apk"

# 4. no copy anywhere: failure 1, nothing written
patched_car t4; rm -f "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk"
run; check "no stock copy: exit 1" test $RC = 1
check "no stock copy: says so" has "not-stock HKMC_GPM.apk"
check "no stock copy: nothing written" same "$T/system/app/HKMC_GPM.odex" "O:gpm.odex"

# 5. firmware update replaced the odex: foreign, left alone, the rest goes back
patched_car t5; mk "$T/system/app/HKMC_GPM.odex" "NEWFW:odex"; echo FP2 > "$T/data/nemesis/jmk-autoplay-hud/fingerprint"
run; check "foreign odex: exit 0" test $RC = 0
check "foreign odex left alone" same "$T/system/app/HKMC_GPM.odex" "NEWFW:odex"
check "foreign line" has "foreign HKMC_GPM.odex"

# 6. /system read-only and remount refused: 70
patched_car t6; echo "/dev/block/x /system ext4 ro,relatime 0 0" > "$T/proc/mounts"; printf '#!/bin/sh\nexit 1\n' > "$T/system/xbin/nemesis"
run; check "read-only /system: exit 70" test $RC = 70
check "read-only: nothing written" same "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"

# 7. ro /system that NEMESIS can remount
patched_car t7; echo "/dev/block/x /system ext4 ro,relatime 0 0" > "$T/proc/mounts"
run; check "remount then restore: exit 0" test $RC = 0

# 8. a record of a file that is stock already: 10
patched_car t8; cp "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk" "$T/system/app/HKMC_GPM.apk"; cp "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex" "$T/system/app/HKMC_GPM.odex"; rm -f "$T/system/lib/libev6aac.so"
run; check "already stock: exit 10" test $RC = 10

# 9. a recorded file that is neither stock nor ours on the same firmware: not-stock (cannot be told) -> 1
patched_car t9; mk "$T/system/app/HKMC_DiPO.apk" "OTHERTOOL:dipo"
run; check "unknown patched apk: exit 1" test $RC = 1
check "unknown patched apk: line" has "not-stock HKMC_DiPO.apk"
check "unknown: nothing written" same "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"

# 10. an unrecorded result is ours when its md5 is in the shipped known list (made/applied lines lost)
patched_car t10; : > "$T/data/nemesis/jmk-autoplay-hud/applied"; : > "$T/data/nemesis/jmk-autoplay-hud.made"
printf 'HKMC_GPM.apk %s\nHKMC_GPM.odex %s\n' "$(q "$T/system/app/HKMC_GPM.apk")" "$(q "$T/system/app/HKMC_GPM.odex")" > "$WORK/known10"
mk "$T/data/nemesis/jmk-autoplay-hud.made" ""
run; check "no applied/made line and not known: cannot be told, exit 1, nothing written" test $RC = 1
check "  and nothing written" same "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"
JMK_LR_KNOWN=$WORK/known10; export JMK_LR_KNOWN
patched_car t10b; : > "$T/data/nemesis/jmk-autoplay-hud/applied"; mk "$T/data/nemesis/jmk-autoplay-hud.made" "HKMC_DiPO.apk x"
run; check "known list: result restored (exit 0)" test $RC = 0
check "known list: GPM apk back" same "$T/system/app/HKMC_GPM.apk" "S:gpm.apk"
unset JMK_LR_KNOWN

# 11. a hold failure does not stop the restore
patched_car t11; export PM_FAIL=1
run; check "pm disable fails: still exit 0" test $RC = 0; PM_FAIL=

# 13. an odex of ours that no stock copy can replace (an old legacy build's file: recorded as ours, its stock copy gone, nothing in the backup / archive dirs proves one): exit 1, nothing written,
#     so the runner stops before any uninstall (evaluator state "unknown_legacy")
patched_car t13; rm -f "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex"
run; check "odex of ours without a stock copy: exit 1" test $RC = 1
check "  line names the odex" has "not-stock HKMC_GPM.odex"
check "  the odex is untouched" same "$T/system/app/HKMC_GPM.odex" "O:gpm.odex"
check "  the apk is untouched too (nothing is written when one file cannot go back)" same "$T/system/app/HKMC_GPM.apk" "O:gpm.apk"
check "  the converter is still there" test -e "$T/system/lib/libev6aac.so"
check "  no app was stopped" bash -c "! grep -q 'pm disable' '$T/pm.log'"
runv; check "  verify says not stock (1)" test $RC = 1
patched_car t13b; rm -f "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex" "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk"; mk "$T/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex" "S:some-other-odex"
run; check "odex of ours and the only copy is not its stock (md5 differs from the record): exit 1, nothing written" test $RC = 1
check "  odex untouched" same "$T/system/app/HKMC_GPM.odex" "O:gpm.odex"

# 12. script runs under bash too (the car's shell is mksh)
patched_car t12; OUT=$(JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims bash "$SC/legacy-restore.sh" 2>&1); RC=$?
check "bash run: exit 0" test $RC = 0

echo "---- $PASS passed, $FAILN failed"
[ $FAILN -eq 0 ]
