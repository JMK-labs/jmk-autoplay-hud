#!/usr/bin/env bash
# lp/package postinstall.sh, svc/hud.sh, preuninstall.sh in a fake car root: the status file the MAP menu reads, the settings bridge.
here="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lp-svc.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { case "$1" in sys.boot_completed) echo 1 ;; ro.build.product) echo NEEV.KOR.0000.V039.001.260902 ;; *) grep "^$1=" "$JMK_HUD_TEST_ROOT/props" 2>/dev/null | { IFS== read -r k v; echo "$v"; } ;; esac; }
setprop() { echo "$1=$2" >> "$JMK_HUD_TEST_ROOT/setprop.log"; grep -v "^$1=" "$JMK_HUD_TEST_ROOT/props" > "$JMK_HUD_TEST_ROOT/props.n" 2>/dev/null; echo "$1=$2" >> "$JMK_HUD_TEST_ROOT/props.n"; mv "$JMK_HUD_TEST_ROOT/props.n" "$JMK_HUD_TEST_ROOT/props"; }
sleep() { :; }
SH
printf '#!/bin/sh\n[ "$1" = check ] && echo "status=$LPSTATE"; exit 0\n' > "$WORK/lpatch"; chmod +x "$WORK/lpatch"
car() {   # car <name>: a fresh root and a package copy; $T $P
    T=$WORK/car.$1; P=$T/data/nemesis/apps/jmk-autoplay-hud; rm -rf "$T"
    mkdir -p "$P" "$T/system/xbin" "$T/system/lib" "$T/proc/sys/kernel/random" "$T/data/nemesis/apps/jmk-autoplay" "$T/data/local/tmp/jmk-autoplay-hud"
    cp -R "$here/../package/." "$P/"; mkdir -p "$P/tools/patches/bycode/kr"; cp "$here/../../package/patches/bycode/kr/knobs" "$P/tools/patches/bycode/kr/"
    printf 'id=jmk-autoplay-hud\npackage-version=0.3.0\n' > "$P/NEMESIS.data"
    echo boot-A > "$T/proc/sys/kernel/random/boot_id"; : > "$T/props"; : > "$T/setprop.log"
    cat > "$P/tools/hud-step" <<'S'
#!/bin/sh
[ "$1" = profile ] || exit 1
echo "$PROFILE_LINE"; [ "$PROFILE_LINE" = profile=none ] && exit 10; exit 0
S
    cat > "$T/system/xbin/nemesis" <<'N'
#!/bin/sh
[ "$1 $2" = "livepatch status" ] && { printf '%s\n' "$LPS"; exit 0; }
exit 0
N
    chmod +x "$T/system/xbin/nemesis" "$P/tools/hud-step"; echo lib > "$T/system/lib/libCarPlayUtils.so"
    export PROFILE_LINE="profile=kr parts=2_tbt 3_bridge apps=HKMC_GPM,HKMC_DiPO libs=libautoreceiver_infobank.so" LPS=$'wrapper=1 safe=0\n/system/app/HKMC_GPM.odex mounted\n/system/app/HKMC_DiPO.odex mounted\n/system/lib/libautoreceiver_infobank.so mounted' LPSTATE=NATIVE
}
env_run() { env JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims JMK_LPATCH=$WORK/lpatch JMK_HUD_PKG=$P JMK_HUD_ONCE=1 "$@"; }
post() { (cd "$P" && env_run sh ./scripts/postinstall.sh) > "$WORK/out" 2>&1; RC=$?; }
svc() { env_run sh "$P/svc/hud.sh" > "$WORK/out" 2>&1; RC=$?; }
st() { local l; while IFS= read -r l; do case "$l" in "$1="*) echo "${l#*=}"; return ;; esac; done < "$T/data/nemesis/jmk-autoplay-hud/status"; }

car a; post
check "postinstall: exit 0" test $RC = 0
check "postinstall: state=reboot" test "$(st state)" = reboot
check "postinstall: set=kr" test "$(st set)" = kr
check "postinstall: installed mark" test -f "$T/data/nemesis/jmk-autoplay-hud/installed"
check "postinstall: converter=native in the status" test "$(st converter)" = native
check "postinstall: knobs of the profile" test "$(st knobs)" = "log,lane_dist,cp_lanes,cp_keepbt"
check "postinstall: settings applied (log=1)" grep -q "persist.leafia.log=1" "$T/setprop.log"
check "postinstall: cp_keepbt on by default" grep -q "persist.leafia.cp.keepbt=1" "$T/setprop.log"
# same boot, nothing mounted yet: reboot
export LPS=$'wrapper=1 safe=0'; svc
check "service same boot, nothing mounted: reboot" test "$(st state)" = reboot
# next boot, all mounted: active, with the tags
echo boot-B > "$T/proc/sys/kernel/random/boot_id"; export LPS=$'wrapper=1 safe=0\n/system/app/HKMC_GPM.odex mounted\n/system/app/HKMC_DiPO.odex mounted\n/system/lib/libautoreceiver_infobank.so mounted\n/system/lib/libCarPlayCore.so mounted'
svc
check "next boot, mounted: active" test "$(st state)" = active
check "  patched tags" test "$(st patched)" = "gpm,dipo,lib,core"
# next boot, nothing mounted: failed
export LPS=$'wrapper=1 safe=0\n/system/app/HKMC_GPM.odex mounted'; svc
check "next boot, DiPO not mounted: failed" test "$(st state)" = failed
check "  reason names it" bash -c "grep -q 'HKMC_DiPO' <<< \"$(st reason)\""
# unmounted by the boot check
export LPS=$'wrapper=1 safe=0\n/system/app/HKMC_GPM.odex unmounted\n/system/app/HKMC_DiPO.odex mounted'; svc
check "an unmounted target: failed" test "$(st state)" = failed
check "  reason says taken down" bash -c "grep -q 'took these down' <<< \"$(st reason)\""
# no profile: locked, reason not Hangul
export PROFILE_LINE=profile=none; svc
check "no profile: locked" test "$(st state)" = locked
check "  reason is ASCII (MAP asks for files only when it is not Korean)" bash -c "LC_ALL=C; [[ \"$(st reason)\" != *[$'\\x80'-$'\\xff']* ]]"
# the stock could not be read: not "locked" (that would ask for files and say the firmware is unsupported)
export PROFILE_LINE="profile=none (the stock could not be read)"; svc
check "stock unreadable: failed, not locked" test "$(st state)" = failed
check "  reason says the stock could not be read" bash -c "grep -q 'could not be read' <<< \"$(st reason)\""
# safe mode
export PROFILE_LINE="profile=kr parts=2_tbt apps=HKMC_GPM libs=" LPS=$'wrapper=1 safe=1'; : > "$T/setprop.log"; svc
check "safe mode: failed with its reason" test "$(st state)" = failed
check "  no settings written in safe mode" test ! -s "$T/setprop.log"
# converter needed shows in the status
export LPSTATE=PATCHABLE LPS=$'wrapper=1 safe=0\n/system/app/HKMC_GPM.odex mounted'; svc
check "converter=needed in the status" test "$(st converter)" = needed
export LPSTATE=NATIVE
# the config
car b; post; mkdir -p "$T/data/local/tmp/jmk-autoplay-hud"; printf 'cp_keepbt=0\nlog=0\n' > "$T/data/local/tmp/jmk-autoplay-hud/config"
echo boot-B > "$T/proc/sys/kernel/random/boot_id"; : > "$T/setprop.log"; svc
check "config: cp_keepbt=0 written" grep -q "persist.leafia.cp.keepbt=0" "$T/setprop.log"
check "config: log=0 written" grep -q "persist.leafia.log=0" "$T/setprop.log"
# uninstall
(cd "$P" && env_run sh ./scripts/preuninstall.sh) > "$WORK/out" 2>&1; check "preuninstall: exit 0" test $? = 0
check "preuninstall: status gone" test ! -e "$T/data/nemesis/jmk-autoplay-hud/status"
check "preuninstall: switches cleared" bash -c "grep -q 'persist.leafia.cp.keepbt=\$' '$T/props'"
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
