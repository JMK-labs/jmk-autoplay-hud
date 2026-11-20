#!/usr/bin/env bash
# jmk-autoplay-hud: the install hooks and the settings service on the Mac, in a fake car root (JMK_HUD_TEST_ROOT).
# A sandbox copy of package/ gets fake patch data (a fake neev_kr set with the real set's shape: 2_tbt + 3_bridge +
# PhoneProjection), fake recipes and stubs for lpatch (ARM), dexopt and the NEMESIS remount; getprop/setprop/pm/md5
# are shell shims appended to its common.sh (PATH put back to the host's after common.sh sets the Android one).
here="$(cd "$(dirname "$0")" && pwd)"
PKGDIR="$here/../package"
HOST_PATH=$PATH
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-autoplay-hud-test.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
RESULTS=$WORK/results
: > "$RESULTS"

ok()   { echo "ok    $1"; echo ok >> "$RESULTS"; }
fail() { echo "FAIL  $1${2:+: $2}"; echo fail >> "$RESULTS"; }
check()     { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
check_not() { local n=$1; shift; if "$@"; then fail "$n"; else ok "$n"; fi; }
q() { md5 -q "$1" 2>/dev/null; }
same_file() { cmp -s "$1" "$2"; }

# ---------------------------------------------------------------- shims appended to the sandbox common.sh
shims() {
cat <<'EOF'
PATH=$HOST_PATH
md5() { command md5 -r "$1" 2>/dev/null; }
parent_cmdline() { cat "$JMK_HUD_TEST_ROOT/parent.cmdline" 2>/dev/null; }
df() { if [ -n "$DF_FREE" ]; then echo "Filesystem Size Used Free Blksize"; echo "$1 1.5G 1.0G $DF_FREE 4096"; else command df -k "$1"; fi; }
getprop() {
    local l
    while IFS= read -r l; do case "$l" in "$1="*) echo "${l#*=}"; return 0 ;; esac; done < "$PROPFILE"
    echo
}
setprop() {
    echo "$1=$2" >> "$JMK_HUD_TEST_ROOT/setprop.log"
    grep -v "^$1=" "$PROPFILE" > "$PROPFILE.n"; echo "$1=$2" >> "$PROPFILE.n"; command mv "$PROPFILE.n" "$PROPFILE"
}
app_process() {   # the JVM runs the package's own CodeSum class (compiled from src/ into $CODESUM_CLASSES)
    [ -n "$CODESUM_HANG" ] && { command sleep 60; return 0; }
    [ "$1 $2" = "/system/bin jmkhud.CodeSum" ] || return 1
    shift 2
    command java -cp "$CODESUM_CLASSES" jmkhud.CodeSum "$@"
}
pm() {
    local d=$JMK_HUD_TEST_ROOT/pm.disabled
    touch "$d"; echo "pm $*" >> "$JMK_HUD_TEST_ROOT/pm.log"
    case "$1 $2" in
        "list packages")
            case " $PM_PKGS " in *" $4 "*) ;; *) return 0 ;; esac
            if [ "$3" = -e ]; then grep -qx "$4" "$d" || echo "package:$4"; else grep -qx "$4" "$d" && echo "package:$4"; fi
            return 0 ;;
    esac
    case "$1" in
        disable) [ -n "$PM_FAIL" ] && return 1; grep -qx "$2" "$d" || echo "$2" >> "$d" ;;
        enable) grep -vx "$2" "$d" > "$d.n"; command mv "$d.n" "$d" ;;
    esac
    return 0
}
EOF
}

CODESUM_CLASSES=$WORK/codesum-classes; export CODESUM_CLASSES
mkdir -p "$CODESUM_CLASSES" && javac -d "$CODESUM_CLASSES" "$here/../src/jmkhud/CodeSum.java"
APPS="HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL PhoneProjection"
LIBS="libautoreceiver_infobank.so libCarPlayAudio.so libCarPlayCore.so libCarPlayUtils.so"
PM_PKGS="com.google.android.projection.sink com.daudio.app.dipo com.tcc.iap2server com.mnsoft.navi com.daudio.app.phoneprojection"
export PM_PKGS
export BLOCKSIZE=1024   # the Mac's ls -s in KB, as toolbox ls -s

# want_app <name> <payload>: what the stub lpatch rebuilds (the stock apk + "dex <payload>")
want_app() { { cat "$ROOT/stock/$1.apk"; echo "dex $2"; } | md5 -q; }
want_file() { echo "dex $1" | md5 -q; }
lpd() { echo "FAKELPD $(q "$ROOT/stock/$2") $3" > "$HP/patches/$1"; }

# A fresh fake car: stock files, a sandbox package with fake patches/recipes and stubs.
setup() {
    ROOT=$(mktemp -d "$WORK/car.XXXXXX")
    S=$ROOT/data/nemesis/jmk-autoplay-hud
    export JMK_HUD_TEST_ROOT=$ROOT HOST_PATH
    mkdir -p "$ROOT/system/app" "$ROOT/system/lib" "$ROOT/system/bin" "$ROOT/system/xbin" "$ROOT/system/etc/permissions" \
             "$ROOT/data/nemesis/apps/jmk-autoplay" "$ROOT/data/local/tmp/jmk-autoplay-hud" "$ROOT/data/dalvik-cache" \
             "$ROOT/proc/sys/kernel/random" "$ROOT/stock"
    for a in $APPS; do
        echo "stock $a.apk" > "$ROOT/stock/$a.apk"; echo "stock $a.odex" > "$ROOT/stock/$a.odex"
    done
    for l in $LIBS; do echo "stock $l" > "$ROOT/stock/$l"; done
    cp "$ROOT"/stock/*.apk "$ROOT"/stock/*.odex "$ROOT/system/app/"
    cp "$ROOT"/stock/*.so "$ROOT/system/lib/"
    echo "boot-1" > "$ROOT/proc/sys/kernel/random/boot_id"
    echo "/dev/block/system /system ext4 rw,relatime 0 0" > "$ROOT/proc/mounts"
    : > "$ROOT/data/dalvik-cache/system@app@HKMC_GPM.apk@classes.dex"     # stale entries (an earlier install)
    : > "$ROOT/data/dalvik-cache/system@app@HKMC_DiPO.apk@classes.dex"
    : > "$ROOT/data/dalvik-cache/system@app@Other.apk@classes.dex"         # not ours: stays
    PROPFILE=$ROOT/props; export PROPFILE
    printf '%s\n' "ro.build.product=NEEV.KOR.0000.V039.001.260902" "sys.boot_completed=1" "persist.leafia.lane.mode=6" "ro.build.fingerprint=hyundai/neev_kr/neev:4.4.2/V039/260902:user/release-keys" > "$PROPFILE"
    : > "$ROOT/setprop.log"; : > "$ROOT/pm.log"; : > "$ROOT/nemesis.log"
    cat > "$ROOT/system/bin/dexopt" <<'EOF'
#!/bin/bash
[ -n "$DEXOPT_FAIL" ] && exit 1
[ "$1" = --preopt ] || exit 1
echo "odex of $(md5 -q "$2")" > "$3"
EOF
    cat > "$ROOT/system/xbin/nemesis" <<'EOF'
#!/bin/bash
echo "$*" >> "$JMK_HUD_TEST_ROOT/nemesis.log"
[ "$1 $2" = "remount rw" ] && [ -z "$NEMESIS_FAIL" ] && echo "/dev/block/system /system ext4 rw,relatime 0 0" > "$JMK_HUD_TEST_ROOT/proc/mounts"
exit 0
EOF
    chmod 0755 "$ROOT/system/bin/dexopt" "$ROOT/system/xbin/nemesis"

    HP=$ROOT/pkg
    cp -R "$PKGDIR" "$HP"
    shims >> "$HP/scripts/common.sh"
    rm -rf "$HP/patches" "$HP/recipes"
    mkdir -p "$HP/patches/neev_kr" "$HP/patches/other" "$HP/recipes"
    printf '%s\n' "NEEV.KOR.0000.V039.001.260902 neev_kr Hyundai Ioniq 5 Korea (test)" "# comment" "CVEV.USA. other Some other car" > "$HP/patches/cars"
    : > "$HP/patches/neev_kr/stock"
    for a in $APPS; do
        echo "$a.apk $(q "$ROOT/stock/$a.apk")" >> "$HP/patches/neev_kr/stock"
        echo "$a.odex $(q "$ROOT/stock/$a.odex")" >> "$HP/patches/neev_kr/stock"
    done
    echo "libautoreceiver_infobank.so $(q "$ROOT/stock/libautoreceiver_infobank.so")" >> "$HP/patches/neev_kr/stock"
    lpd neev_kr/HKMC_GPM.tbt.lpd HKMC_GPM.odex gpm-tbt
    lpd neev_kr/HKMC_Navi_ExSL.tbt.lpd HKMC_Navi_ExSL.odex navi-tbt
    lpd neev_kr/lib.tbt.lpd libautoreceiver_infobank.so lib-tbt
    lpd neev_kr/Iap2ServerApp.bridge.lpd Iap2ServerApp.odex iap2-bridge
    lpd neev_kr/HKMC_DiPO.bridge.lpd HKMC_DiPO.odex dipo-bridge
    lpd neev_kr/PhoneProjection.bridge.lpd PhoneProjection.odex pp-bridge
    # the 2_tbt DiPO / Iap2 patches are not there: the 3_bridge lines replace them (never read)
    {
        echo "2_tbt app HKMC_GPM neev_kr/HKMC_GPM.tbt.lpd $(want_app HKMC_GPM gpm-tbt)"
        echo "2_tbt app HKMC_DiPO neev_kr/HKMC_DiPO.tbt.lpd 00000000000000000000000000000000"
        echo "2_tbt app Iap2ServerApp neev_kr/Iap2ServerApp.tbt.lpd 00000000000000000000000000000000"
        echo "2_tbt app HKMC_Navi_ExSL neev_kr/HKMC_Navi_ExSL.tbt.lpd $(want_app HKMC_Navi_ExSL navi-tbt)"
        echo "2_tbt file libautoreceiver_infobank.so neev_kr/lib.tbt.lpd $(want_file lib-tbt)"
        echo "3_bridge app Iap2ServerApp neev_kr/Iap2ServerApp.bridge.lpd $(want_app Iap2ServerApp iap2-bridge)"
        echo "3_bridge app HKMC_DiPO neev_kr/HKMC_DiPO.bridge.lpd $(want_app HKMC_DiPO dipo-bridge)"
        echo "3_bridge app PhoneProjection neev_kr/PhoneProjection.bridge.lpd $(want_app PhoneProjection pp-bridge)"
    } > "$HP/patches/neev_kr/manifest"
    echo "log lane_dist cp_lanes" > "$HP/patches/neev_kr/knobs"
    echo "HKMC_GPM.apk 11111111111111111111111111111111" > "$HP/patches/other/stock"
    echo "2_tbt app HKMC_GPM other/x.lpd 22222222222222222222222222222222" > "$HP/patches/other/manifest"
    # recipes: audio fits (PATCHABLE), core and utils are NATIVE on this fake firmware (as on KR 260902)
    printf '%s\n' "id carplay-audio-formats" "file /system/lib/libCarPlayAudio.so" "stock $(q "$ROOT/stock/libCarPlayAudio.so")" > "$HP/recipes/carplay-audio-formats.recipe"
    printf '%s\n' "id carplay-core-wifi" "file /system/lib/libCarPlayCore.so" "stock 0" "native $(q "$ROOT/stock/libCarPlayCore.so")" > "$HP/recipes/carplay-core-wifi.recipe"
    printf '%s\n' "id carplay-utils-converter" "file /system/lib/libCarPlayUtils.so" "stock 0" "native $(q "$ROOT/stock/libCarPlayUtils.so")" > "$HP/recipes/carplay-utils-converter.recipe"
    cat > "$HP/tools/lpatch" <<'EOF'
#!/bin/bash
# stub of Leafia's lpatch: FAKELPD <source md5> <payload> deltas, "stock/native" recipes that append a marker line
q() { md5 -q "$1" 2>/dev/null; }
rv() { local k v; while read -r k v; do [ "$k" = "$2" ] && { echo "$v"; return; }; done < "$1"; }
rstate() {
    [ -f "$2" ] || { echo MISSING; return; }
    if [ "$(tail -n 1 "$2")" = "patched $(rv "$1" id)" ]; then echo APPLIED
    elif [ "$(q "$2")" = "$(rv "$1" stock)" ]; then echo PATCHABLE
    elif [ "$(q "$2")" = "$(rv "$1" native)" ]; then echo NATIVE
    else echo MISMATCH; fi
}
case "$1" in
    delta)
        read -r magic src payload < "$2" 2>/dev/null || { echo "missing patch"; exit 1; }
        [ "$magic" = FAKELPD ] || { echo "not an lpatch delta"; exit 1; }
        [ "$(q "$3")" = "$src" ] || { echo "RESULT delta status=MISMATCH file=$3"; exit 1; }
        echo "dex $payload" > "$4"; echo "RESULT delta status=BUILT file=$4" ;;
    zipadd) cat "$2" "$3" > "$4" && echo "RESULT zipadd status=BUILT file=$4" ;;
    check) echo "RESULT check status=$(rstate "$2" "$3") file=$3" ;;
    apply)
        [ "$(rstate "$2" "$3")" = PATCHABLE ] || { echo "RESULT apply status=MISMATCH"; exit 1; }
        { cat "$3"; echo "patched $(rv "$2" id)"; } > "$4" ;;
    md5) md5 -r "$2" ;;
    *) exit 2 ;;
esac
EOF
    chmod 0755 "$HP/tools/lpatch"
}
hook() { (cd "$HP" && bash "scripts/$1.sh") > "$ROOT/$1.out" 2>&1; }
svc() { JMK_HUD_PKG=$HP JMK_HUD_ONCE=1 bash "$HP/svc/hud.sh" > "$ROOT/svc.out" 2>&1; }
st() { local l; while IFS= read -r l; do case "$l" in "$1="*) echo "${l#*=}"; return; esac; done < "$ROOT/data/nemesis/jmk-autoplay-hud/status"; }
prop() { local l; while IFS= read -r l; do case "$l" in "$1="*) echo "${l#*=}"; return; esac; done < "$PROPFILE"; echo; }
all_stock() {   # every system file byte-identical to the stock copy
    local a l
    for a in $APPS; do same_file "$ROOT/stock/$a.apk" "$ROOT/system/app/$a.apk" && same_file "$ROOT/stock/$a.odex" "$ROOT/system/app/$a.odex" || return 1; done
    for l in $LIBS; do same_file "$ROOT/stock/$l" "$ROOT/system/lib/$l" || return 1; done
    [ ! -e "$ROOT/system/lib/libev6aac.so" ]
}
snap() { (cd "$ROOT/system" && find . -type f -exec md5 -r {} \; | sort) > "$1"; }
no_ro() { ! grep -q 'ro' "$ROOT/nemesis.log"; }
stage_update() { mkdir -p "$ROOT/data/local/tmp/nemesis/stage/jmk-autoplay-hud"; echo "id=jmk-autoplay-hud" > "$ROOT/data/local/tmp/nemesis/stage/jmk-autoplay-hud/NEMESIS.data"; echo "/system/xbin/nemesis install --update /data/local/tmp/jmk-autoplay-hud-0.1.8.zip" > "$ROOT/parent.cmdline"; }
unstage() { rm -rf "$ROOT/data/local/tmp/nemesis" "$ROOT/parent.cmdline"; }

# ---------------------------------------------------------------- preinstall
(
    setup
    hook preinstall; check "preinstall: jmk-autoplay there, nothing else -> exit 0" [ $? -eq 0 ]
    rmdir "$ROOT/data/nemesis/apps/jmk-autoplay"
    hook preinstall; check "preinstall: no jmk-autoplay -> refused" [ $? -eq 1 ]
    check "preinstall: says to install jmk-autoplay first" grep -q 'jmk-autoplay' "$ROOT/preinstall.out"
    mkdir -p "$ROOT/data/nemesis/packages/jmk-autoplay"
    hook preinstall; check "preinstall: jmk-autoplay under packages/ counts" [ $? -eq 0 ]
    mkdir "$ROOT/data/nemesis/apps/jmk-map-menu" "$ROOT/data/nemesis/apps/jmk-wifi" "$ROOT/data/nemesis/apps/jmk.x"
    hook preinstall; check "preinstall: our own packages (jmk-*, jmk.*) never count" [ $? -eq 0 ]
    for id in wireless.cp.aa.neev.kor wireless.carplay.aa wireless.projection projection.tbt wireless.carplay.bt carplay.session \
              danpung danpung.update korea.projection aa.usbwifi leafia.ioniq5.kr.combined.tbt my-evergreen androidauto.x; do
        mkdir "$ROOT/data/nemesis/apps/$id"
        hook preinstall; rc=$?
        check "preinstall: refused next to $id" eval '[ $rc -eq 1 ] && grep -q "$id" "$ROOT/preinstall.out"'
        rmdir "$ROOT/data/nemesis/apps/$id"
    done
    mkdir -p "$ROOT/data/hmgapi/mods/wireless-carplay-aa"
    hook preinstall; check "preinstall: refused next to an HMG-API projection mod" [ $? -eq 1 ]
    mkdir -p "$ROOT/data/nemesis/jmk-autoplay-hud"; : > "$ROOT/data/nemesis/jmk-autoplay-hud/installed"
    hook preinstall; check "preinstall: an update always goes ahead" [ $? -eq 0 ]
)

# ---------------------------------------------------------------- install, service, update, uninstall
(
    setup
    echo "/dev/block/system /system ext4 ro,relatime 0 0" > "$ROOT/proc/mounts"   # read-only at the start
    echo "com.daudio.app.phoneprojection" > "$ROOT/pm.disabled"                 # the owner disabled one app
    hook postinstall; rc=$?
    check "install: exit 0" [ $rc -eq 0 ]
    check "install: state=reboot" [ "$(st state)" = reboot ]
    check "install: set=neev_kr" [ "$(st set)" = neev_kr ]
    check "install: ver=0.1.14" [ "$(st ver)" = 0.1.14 ]
    check "install: patched = every target + the audio recipe" [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ]
    check "install: knobs=log,lane_dist,cp_lanes" [ "$(st knobs)" = "log,lane_dist,cp_lanes" ]
    check "install: reason empty" [ -z "$(st reason)" ]
    for a in HKMC_GPM:gpm-tbt HKMC_Navi_ExSL:navi-tbt Iap2ServerApp:iap2-bridge HKMC_DiPO:dipo-bridge PhoneProjection:pp-bridge; do
        n=${a%%:*}; p=${a#*:}
        check "install: $n.apk is the rebuilt one ($p)" [ "$(q "$ROOT/system/app/$n.apk")" = "$(want_app "$n" "$p")" ]
        check "install: $n.odex written by dexopt from it" [ "$(cat "$ROOT/system/app/$n.odex")" = "odex of $(q "$ROOT/system/app/$n.apk")" ]
    done
    check "install: the 3_bridge build replaced the 2_tbt one (no tbt DiPO/Iap2 built)" eval '! grep -q "HKMC_DiPO.tbt\|Iap2ServerApp.tbt" "$ROOT/data/nemesis/jmk-autoplay-hud.log"'
    check "install: receiver library rebuilt" [ "$(q "$ROOT/system/lib/libautoreceiver_infobank.so")" = "$(want_file lib-tbt)" ]
    check "install: libCarPlayAudio patched by its recipe" [ "$(tail -n 1 "$ROOT/system/lib/libCarPlayAudio.so")" = "patched carplay-audio-formats" ]
    check "install: NATIVE core and utils untouched" eval 'same_file "$ROOT/stock/libCarPlayCore.so" "$ROOT/system/lib/libCarPlayCore.so" && same_file "$ROOT/stock/libCarPlayUtils.so" "$ROOT/system/lib/libCarPlayUtils.so"'
    check "install: no converter added (utils NATIVE)" [ ! -e "$ROOT/system/lib/libev6aac.so" ]
    B=$ROOT/data/nemesis/backups/jmk-autoplay-hud
    n=0; for f in "$ROOT"/stock/*; do b=${f##*/}; case "$b" in libCarPlayCore.so|libCarPlayUtils.so) continue ;; esac; same_file "$f" "$B/$b" && n=$((n+1)); done
    check "install: 12 stock copies kept, byte-identical" [ $n -eq 12 ]
    check "install: the stock list has 12 lines" [ "$(grep -c . "$ROOT/data/nemesis/jmk-autoplay-hud/stock")" -eq 12 ]
    check "install: NEMESIS asked for rw once (it was ro)" [ "$(grep -c 'remount rw' "$ROOT/nemesis.log")" -eq 1 ]
    check "install: never remount ro" no_ro
    check "install: enabled apps stopped for the swap" [ "$(grep -c '^pm disable' "$ROOT/pm.log")" -eq 4 ]
    check "install: ... and started again" [ "$(grep -c '^pm enable' "$ROOT/pm.log")" -eq 4 ]
    check "install: the owner's disabled app stays disabled" eval '[ "$(cat "$ROOT/pm.disabled")" = com.daudio.app.phoneprojection ]'
    check "install: no stopped-apps list left" [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud/stopped" ]
    check "install: someone else's dalvik-cache entry stays" [ -e "$ROOT/data/dalvik-cache/system@app@Other.apk@classes.dex" ]
    check "install: dalvik-cache filled with the new odex" same_file "$ROOT/system/app/HKMC_GPM.odex" "$ROOT/data/dalvik-cache/system@app@HKMC_GPM.apk@classes.dex"
    check "install: no build dir left" [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud/build" ]
    check "install: no temp file next to a target" eval '! ls "$ROOT"/system/app/*.jmkhud "$ROOT"/system/lib/*.jmkhud >/dev/null 2>&1'
    check "install: no warning" [ -z "$(st warn)" ]
    check "install: status file 0644" [ "$(stat -f %Lp "$ROOT/data/nemesis/jmk-autoplay-hud/status")" = 644 ]

    : > "$ROOT/setprop.log"
    svc; rc=$?
    check "service, same boot: exit 0" [ $rc -eq 0 ]
    check "service, same boot: state stays reboot" [ "$(st state)" = reboot ]
    check "service: no config -> log=1, lane.log=1, lane.dist=label, cp.lanes=1" \
        [ "$(prop persist.leafia.log)/$(prop persist.leafia.lane.log)/$(prop persist.leafia.lane.dist)/$(prop persist.leafia.cp.lanes)" = "1/1/label/1" ]
    check "service: a retired switch left by Leafia is cleared" [ -z "$(prop persist.leafia.lane.mode)" ]
    echo "boot-2" > "$ROOT/proc/sys/kernel/random/boot_id"
    : > "$ROOT/setprop.log"
    svc
    check "service, next boot: state=active" [ "$(st state)" = active ]
    check "service, next boot: switches already right -> no setprop" [ ! -s "$ROOT/setprop.log" ]
    printf '%s\n' on_cluster=1 look=simple log=0 lane_dist=0 cp_lanes=0 lanes=0 ar_dist=500 > "$ROOT/data/local/tmp/jmk-autoplay-hud/config"
    svc
    check "service: config log=0 lane_dist=0 cp_lanes=0 -> 0/0/off/0" \
        [ "$(prop persist.leafia.log)/$(prop persist.leafia.lane.log)/$(prop persist.leafia.lane.dist)/$(prop persist.leafia.cp.lanes)" = "0/0/off/0" ]
    check "service: keys without a switch set nothing" [ "$(grep -vc '^persist\.leafia\.\(log\|lane\.log\|lane\.dist\|cp\.lanes\)=' "$ROOT/setprop.log")" -eq 0 ]
    printf '%s\n' log=yes lane_dist=2 > "$ROOT/data/local/tmp/jmk-autoplay-hud/config"
    svc
    check "service: invalid values -> the defaults" [ "$(prop persist.leafia.log)/$(prop persist.leafia.lane.dist)/$(prop persist.leafia.cp.lanes)" = "1/label/1" ]

    snap "$ROOT/after-install"
    stage_update
    hook preuninstall; rc=$?
    check "update's preuninstall: exit 0" [ $rc -eq 0 ]
    snap "$ROOT/after-preun"
    check "update's preuninstall: every file stays" cmp -s "$ROOT/after-install" "$ROOT/after-preun"
    check "update's preuninstall: records and backups stay" eval '[ -s "$ROOT/data/nemesis/jmk-autoplay-hud/applied" ] && [ -d "$ROOT/data/nemesis/backups/jmk-autoplay-hud" ]'
    hook postinstall; rc=$?
    snap "$ROOT/after-update"
    check "update, same patches: exit 0" [ $rc -eq 0 ]
    check "update, same patches: nothing changed" cmp -s "$ROOT/after-install" "$ROOT/after-update"
    check "update, same patches: state stays active" [ "$(st state)" = active ]
    check "update, same patches: says so" grep -q 'in place already' "$ROOT/postinstall.out"

    # a new version whose GPM patch differs: rebuilt from our stock copy, the rest untouched
    lpd neev_kr/HKMC_GPM.tbt.lpd HKMC_GPM.odex gpm-tbt-v2
    g2=$(want_app HKMC_GPM gpm-tbt-v2)
    while read -r a b c d e; do [ "$c" = HKMC_GPM ] && e=$g2; echo "$a $b $c $d $e"; done < "$HP/patches/neev_kr/manifest" > "$ROOT/m" && mv "$ROOT/m" "$HP/patches/neev_kr/manifest"
    hook preuninstall
    hook postinstall; rc=$?
    check "update, new GPM patch: exit 0" [ $rc -eq 0 ]
    check "update, new GPM patch: GPM rebuilt from the stock copy" [ "$(q "$ROOT/system/app/HKMC_GPM.apk")" = "$g2" ]
    check "update, new GPM patch: the others untouched" [ "$(q "$ROOT/system/app/HKMC_DiPO.apk")" = "$(want_app HKMC_DiPO dipo-bridge)" ]
    check "update, new GPM patch: state=reboot" [ "$(st state)" = reboot ]
    check "update, new GPM patch: the stock copy is still stock" same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk"
    unstage

    (cd "$HP" && bash bin/status.sh) > "$ROOT/status.out" 2>&1
    check "status.sh: shows the patched GPM" grep -q '^patched HKMC_GPM.apk' "$ROOT/status.out"

    : > "$ROOT/pm.log"
    hook preuninstall; rc=$?
    check "uninstall: exit 0" [ $rc -eq 0 ]
    check "uninstall: every stock file byte-identical" all_stock
    check "uninstall: backups removed" [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud" ]
    check "uninstall: state removed" [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud" ]
    check "uninstall: the switches cleared" [ -z "$(prop persist.leafia.log)$(prop persist.leafia.lane.dist)$(prop persist.leafia.cp.lanes)" ]
    check "uninstall: our dalvik-cache entries gone" eval '[ ! -e "$ROOT/data/dalvik-cache/system@app@HKMC_GPM.apk@classes.dex" ] && [ ! -e "$ROOT/data/dalvik-cache/system@app@PhoneProjection.apk@classes.dex" ]'
    check "uninstall: someone else's entry stays" [ -e "$ROOT/data/dalvik-cache/system@app@Other.apk@classes.dex" ]
    check "uninstall: apps stopped and started again" [ "$(grep -c '^pm disable' "$ROOT/pm.log")" -eq "$(grep -c '^pm enable' "$ROOT/pm.log")" ]
    check "uninstall: the owner's disabled app still disabled" eval '[ "$(cat "$ROOT/pm.disabled")" = com.daudio.app.phoneprojection ]'
    check "uninstall: the log is kept" [ -s "$ROOT/data/nemesis/jmk-autoplay-hud.log" ]
    check "never remount ro (whole run)" no_ro
)

# ---------------------------------------------------------------- root without capabilities: dalvik-cache closed
(
    setup
    chmod 0555 "$ROOT/data/dalvik-cache"
    hook postinstall; rc=$?
    check "capless install: exit 0" [ $rc -eq 0 ]
    check "capless install: state=reboot, all patched" eval '[ "$(st state)" = reboot ] && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ]'
    check "capless install: warn names the entries left" eval 'case "$(st warn)" in *HKMC_GPM.apk*) true ;; *) false ;; esac'
    check "capless install: logged as harmless" grep -q 'harmless' "$ROOT/postinstall.out"
    check "capless install: cache not filled, the boot optimises" grep -q 'not filled' "$ROOT/postinstall.out"
    hook preuninstall; rc=$?
    check "capless uninstall: exit 0 (never aborts on the cache)" [ $rc -eq 0 ]
    check "capless uninstall: every stock file byte-identical" all_stock
    check "capless uninstall: warned" grep -q 'WARNING: could not remove' "$ROOT/preuninstall.out"
    check "capless uninstall: state removed" [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud" ]
    chmod 0755 "$ROOT/data/dalvik-cache"
)

# ---------------------------------------------------------------- locked: nothing changed
(
    setup
    echo "leafia patched odex" > "$ROOT/system/app/HKMC_GPM.odex"
    snap "$ROOT/before"
    hook postinstall; rc=$?
    snap "$ROOT/after"
    check "locked (GPM odex not stock): exit 0" [ $rc -eq 0 ]
    check "locked: state=locked" [ "$(st state)" = locked ]
    check "locked: the reason names HKMC_GPM.odex" eval 'case "$(st reason)" in *HKMC_GPM.odex*"not the stock file"*) true ;; *) false ;; esac'
    check "locked: /system unchanged" cmp -s "$ROOT/before" "$ROOT/after"
    check "locked: no stock copies made" eval '[ -z "$(ls "$ROOT/data/nemesis/backups/jmk-autoplay-hud" 2>/dev/null)" ]'
    check "locked: no app stopped, no remount" eval '[ ! -s "$ROOT/pm.log" ] && [ ! -s "$ROOT/nemesis.log" ]'
    check "locked: patched empty" [ -z "$(st patched)" ]
    : > "$ROOT/setprop.log"; svc
    check "locked: the service sets no switch" [ ! -s "$ROOT/setprop.log" ]
    hook preuninstall; rc=$?
    check "locked: uninstall exit 0, nothing touched" eval '[ $rc -eq 0 ] && [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud" ]'
    snap "$ROOT/after2"
    check "locked: uninstall leaves /system as it was" cmp -s "$ROOT/before" "$ROOT/after2"
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=CV.KOR.0000.V030.001.260101/' "$PROPFILE"
    echo "other firmware" > "$ROOT/system/app/HKMC_DiPO.odex"
    mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    hook postinstall; rc=$?
    check "unknown car, files match no set: locked" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ] && [ -z "$(st set)" ]'
    check "unknown car: the reason says no patch set" eval 'case "$(st reason)" in *"no patch set"*) true ;; *) false ;; esac'
    R=$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-postinstall-locked.json
    check "unknown car (0.1.1): the locked report names the product" grep -q 'product CV.KOR.0000.V030.001.260101; live ' "$R"
    check "unknown car (0.1.1): ... and the live md5 of the changed file" grep -q "HKMC_DiPO.odex=$(md5 -q "$ROOT/system/app/HKMC_DiPO.odex")" "$R"
    check "unknown car (0.1.1): ... and of a stock one" grep -q "HKMC_GPM.apk=$(md5 -q "$ROOT/system/app/HKMC_GPM.apk")" "$R"
    check "unknown car: no other-model-set report (nothing applied)" eval '[ ! -e "${R%postinstall-locked.json}other-model-set.json" ]'
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=CV.KOR.0000.V030.001.260101/' "$PROPFILE"
    # a Dalvik odex for DiPO ("dey" header, the dex at 40): its code md5 is the md5 of those dex bytes
    python3 -c "
import struct,sys
dex=b'dex\\n035\\0'+bytes(range(256))*2
hdr=b'dey\\n036\\0'+struct.pack('<8I',40,len(dex),0,0,0,0,0,0)
open(sys.argv[1],'wb').write(hdr+dex+b'deps and opt data of this framework')
open(sys.argv[2],'wb').write(dex)" "$ROOT/system/app/HKMC_DiPO.odex" "$ROOT/dipo.dex"
    mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    hook postinstall; rc=$?
    R=$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-postinstall-locked.json
    check "locked report (0.1.3): the code md5 of DiPO's odex" grep -q "code .*HKMC_DiPO.code=$(md5 -q "$ROOT/dipo.dex")" "$R"
    check "locked report (0.1.3): an odex that is not a Dalvik odex reads none" grep -q "HKMC_GPM.code=none" "$R"
    check "locked report (0.1.3): still exit 0, locked" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ]'
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=CV.KOR.0000.V030.001.260101/' "$PROPFILE"
    echo "other firmware" > "$ROOT/system/app/HKMC_DiPO.odex"
    mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    t0=$(date +%s); CODESUM_HANG=1 hook postinstall; rc=$?; t1=$(date +%s)
    R=$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-postinstall-locked.json
    check "locked report (0.1.3): a hanging helper is stopped after ~20 s, the report goes out" eval '[ $rc -eq 0 ] && [ $((t1 - t0)) -le 30 ] && grep -q "; code" "$R"'
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=NEEV.KOR.0000.V040.001.270101/' "$PROPFILE"
    hook postinstall; rc=$?
    check "product not in cars but every stock file matches: set picked by md5" eval '[ $rc -eq 0 ] && [ "$(st set)" = neev_kr ] && [ "$(st state)" = reboot ]'
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=NEEV.USA.0000.V100.001.270101/' "$PROPFILE"
    mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    hook postinstall; rc=$?
    check "another region, its stock files are the KR set's: applied (0.1.1)" eval '[ $rc -eq 0 ] && [ "$(st set)" = neev_kr ] && [ "$(st state)" = reboot ]'
    check "another region: one other-model-set report with the set and product" \
        grep -q '"detail":"set neev_kr; product NEEV.USA.0000.V100.001.270101"' "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-other-model-set.json"
)

(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=CVEV.USA.0000.V020.001.270101/' "$PROPFILE"
    hook postinstall; rc=$?
    check "product named for a set whose files it lacks, files are another set's: that one (0.1.2)" eval '[ $rc -eq 0 ] && [ "$(st set)" = neev_kr ] && [ "$(st state)" = reboot ]'
)
(
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=CVEV.USA.0000.V020.001.270101/' "$PROPFILE"
    echo "other firmware" > "$ROOT/system/app/HKMC_DiPO.odex"
    hook postinstall; rc=$?
    check "product named for a set, files match no set: locked on the named set (0.1.2)" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ]'
)

# ---------------------------------------------------------------- by code (0.1.4)
# mkodex <app> <seed>: the app's stock odex becomes a Dalvik odex ("dey" header, its framework's bytes after the dex);
# prints the md5 of the dex inside (what tools/codesum.jar reads)
mkodex() {
    python3 -c "
import struct,sys,hashlib
dex=b'dex\n035\0'+(sys.argv[2].encode()*64)[:300]
hdr=b'dey\n036\0'+struct.pack('<8I',40,len(dex),0,0,0,0,0,0)
for p in sys.argv[3:]: open(p,'wb').write(hdr+dex+b'framework checksums of this car')
print(hashlib.md5(dex).hexdigest())" "$1" "$2" "$ROOT/stock/$1.odex" "$ROOT/system/app/$1.odex"
}
# bycode_setup <PhoneProjection seed of the profile>: a car no set fits (GL3HEV), its apps' code = the kr profile's
bycode_setup() {
    setup
    sed -i '' 's/^ro.build.product=.*/ro.build.product=GL3HEV.KOR.0000.V039.001.260902/' "$PROPFILE"
    mkdir -p "$HP/patches/bycode/kr" "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    local a c pp
    : > "$HP/patches/bycode/kr/manifest"
    for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
        c=$(mkodex "$a" "$a-code")
        echo "FAKELPD $c $a-tbt" > "$HP/patches/bycode/kr/$a.tbt.lpd"
        echo "2_tbt app $a $c bycode/kr/$a.tbt.lpd $(want_file "$a-tbt")" >> "$HP/patches/bycode/kr/manifest"
    done
    echo "FAKELPD $(q "$ROOT/stock/libautoreceiver_infobank.so") lib-tbt" > "$HP/patches/bycode/kr/lib.tbt.lpd"
    echo "2_tbt file libautoreceiver_infobank.so $(q "$ROOT/stock/libautoreceiver_infobank.so") bycode/kr/lib.tbt.lpd $(want_file lib-tbt)" >> "$HP/patches/bycode/kr/manifest"
    pp=$(mkodex PhoneProjection PhoneProjection-code)
    [ "$1" = other ] && pp=0123456789abcdef0123456789abcdef
    for a in HKMC_DiPO Iap2ServerApp; do
        c=$(python3 -c "import struct,hashlib;d=open('$ROOT/stock/$a.odex','rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())")
        echo "FAKELPD $c $a-bridge" > "$HP/patches/bycode/kr/$a.bridge.lpd"
        echo "3_bridge app $a $c bycode/kr/$a.bridge.lpd $(want_file "$a-bridge")" >> "$HP/patches/bycode/kr/manifest"
    done
    echo "FAKELPD $pp PhoneProjection-bridge" > "$HP/patches/bycode/kr/PhoneProjection.bridge.lpd"
    echo "3_bridge app PhoneProjection $pp bycode/kr/PhoneProjection.bridge.lpd $(want_file PhoneProjection-bridge)" >> "$HP/patches/bycode/kr/manifest"
    echo "log lane_dist cp_lanes" > "$HP/patches/bycode/kr/knobs"
}
(
    bycode_setup other
    snap "$ROOT/before"
    hook postinstall; rc=$?
    check "by code (0.1.4): no set fits, the code does: set auto, reboot" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ] && [ "$(st state)" = reboot ]'
    check "by code: turn-by-turn only (PhoneProjection's code differs: no bridge)" eval '[ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = 2_tbt ]'
    check "by code: DiPO is its turn-by-turn build in this car's own apk" eval '[ "$(cat "$ROOT/system/app/HKMC_DiPO.apk")" = "$(cat "$ROOT/stock/HKMC_DiPO.apk"; echo "dex HKMC_DiPO-tbt")" ]'
    check "by code: GPM, Navi and the library patched too" eval 'grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && grep -q "dex HKMC_Navi_ExSL-tbt" "$ROOT/system/app/HKMC_Navi_ExSL.apk" && grep -q "dex lib-tbt" "$ROOT/system/lib/libautoreceiver_infobank.so"'
    check "by code: PhoneProjection untouched" same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk"
    check "by code: the profile's knobs" eval '[ "$(st knobs)" = log,lane_dist,cp_lanes ]'
    R=$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-other-model-set.json
    check "by code: one report with profile, parts and code" grep -q 'set auto (profile kr, parts 2_tbt); product GL3HEV.KOR.0000.V039.001.260902; code .*HKMC_DiPO.code=' "$R"
    hook postinstall; rc=$?
    check "by code: again (an update): every target in place, nothing changed" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ] && grep -q "every target is in place already" "$ROOT/postinstall.out"'
    hook preuninstall; rc=$?
    check "by code: uninstall puts every stock file back" eval '[ $rc -eq 0 ] && all_stock'
    check "by code: uninstall leaves no auto set" eval '[ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud/auto" ]'
)
(
    # 0.1.5: an install that left lpatch without its exec bit (K8 cars, 2026-11-17: "can't execute: Permission denied")
    bycode_setup other
    chmod 0644 "$HP/tools/lpatch"
    hook postinstall; rc=$?
    check "by code (0.1.5): lpatch without its exec bit still builds: set auto" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ]'
)
(
    bycode_setup same
    hook postinstall; rc=$?
    check "by code: PhoneProjection's code fits too: both parts" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "by code: DiPO and Iap2 are their bridge builds, PhoneProjection patched" eval 'grep -q "dex HKMC_DiPO-bridge" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex Iap2ServerApp-bridge" "$ROOT/system/app/Iap2ServerApp.apk" && grep -q "dex PhoneProjection-bridge" "$ROOT/system/app/PhoneProjection.apk"'
)
(
    bycode_setup other
    sed -i '' 's/^\(2_tbt app HKMC_GPM [0-9a-f]* [^ ]*\) .*/\1 ffffffffffffffffffffffffffffffff/' "$HP/patches/bycode/kr/manifest"
    snap "$ROOT/before"
    hook postinstall; rc=$?
    snap "$ROOT/after"
    check "by code: a rebuilt code that is not the profile's: locked, nothing changed" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ] && cmp -s "$ROOT/before" "$ROOT/after"'
    check "by code: ... and no auto set left" eval '[ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud/auto" ]'
)
(
    # 0.1.5 krb (Sonata DN8, Avante HEV, ...): the car's code is a second profile's; the first (kr) fits no part of it
    bycode_setup other
    mkdir -p "$HP/patches/bycode/krb"
    grep '^2_tbt ' "$HP/patches/bycode/kr/manifest" | sed 's# bycode/kr/# bycode/krb/#' > "$HP/patches/bycode/krb/manifest"
    cp "$HP/patches/bycode/kr/"*.tbt.lpd "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/krb/"
    sed -i '' 's/^\(2_tbt app HKMC_GPM\) [0-9a-f]*/\1 0123456789abcdef0123456789abcdef/' "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code: a later profile that fits (krb) is used when an earlier one (kr) fits nothing" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = krb ]'
    check "by code: krb: turn-by-turn only, GPM patched" eval '[ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = 2_tbt ] && grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk"'
    check "by code: krb: the report names the profile" grep -q 'set auto (profile krb, parts 2_tbt)' "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-other-model-set.json"
)
(
    # 0.1.6 kra (K8, K8 HEV, Seltos): kr fits the turn-by-turn only (their PhoneProjection differs); kra, after it by
    # name, has kr's lines plus this car's PhoneProjection: the profile with more parts wins
    bycode_setup other
    mkdir -p "$HP/patches/bycode/kra"
    pp=$(python3 -c "import struct,hashlib;d=open('$ROOT/stock/PhoneProjection.odex','rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())")
    grep -v ' PhoneProjection ' "$HP/patches/bycode/kr/manifest" > "$HP/patches/bycode/kra/manifest"
    echo "FAKELPD $pp PhoneProjection-k8bridge" > "$HP/patches/bycode/kra/PhoneProjection.bridge.lpd"
    echo "3_bridge app PhoneProjection $pp bycode/kra/PhoneProjection.bridge.lpd $(want_file PhoneProjection-k8bridge)" >> "$HP/patches/bycode/kra/manifest"
    cp "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/kra/"
    hook postinstall; rc=$?
    check "by code (0.1.6): the profile that fits more parts (kra) wins over an earlier one (kr, turn-by-turn only)" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = kra ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "by code: kra: PhoneProjection is its K8 bridge build, DiPO and Iap2 kr's bridge builds" eval 'grep -q "dex PhoneProjection-k8bridge" "$ROOT/system/app/PhoneProjection.apk" && grep -q "dex HKMC_DiPO-bridge" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex Iap2ServerApp-bridge" "$ROOT/system/app/Iap2ServerApp.apk"'
    check "by code: kra: the report names it" grep -q 'set auto (profile kra, parts 2_tbt 3_bridge)' "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-other-model-set.json"
)
(
    # 0.1.7 krp (Avante CN7PE): every app another code, the results kr's builds: kr fits nothing, krp both parts
    bycode_setup other
    mkdir -p "$HP/patches/bycode/krp"
    pp=$(python3 -c "import struct,hashlib;d=open('$ROOT/stock/PhoneProjection.odex','rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())")
    sed 's# bycode/kr/# bycode/krp/#' "$HP/patches/bycode/kr/manifest" | grep -v ' PhoneProjection ' > "$HP/patches/bycode/krp/manifest"
    cp "$HP/patches/bycode/kr/"*.lpd "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/krp/"
    echo "FAKELPD $pp PhoneProjection-cn7bridge" > "$HP/patches/bycode/krp/PhoneProjection.bridge.lpd"
    echo "3_bridge app PhoneProjection $pp bycode/krp/PhoneProjection.bridge.lpd $(want_file PhoneProjection-cn7bridge)" >> "$HP/patches/bycode/krp/manifest"
    sed -i '' 's/^\(2_tbt app HKMC_GPM\) [0-9a-f]*/\1 0123456789abcdef0123456789abcdef/' "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.7): krp, with both parts, where kr fits nothing" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = krp ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
)
(
    # 0.1.10 kri (Ioniq 6 Korea CEEV): krp's app lines (no library line) and its own PhoneProjection: krp fits the
    # turn-by-turn only (another PhoneProjection), kr nothing; kri wins with both parts and leaves the library stock
    bycode_setup other
    mkdir -p "$HP/patches/bycode/krp" "$HP/patches/bycode/kri"
    pp=$(python3 -c "import struct,hashlib;d=open('$ROOT/stock/PhoneProjection.odex','rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())")
    sed 's# bycode/kr/# bycode/krp/#' "$HP/patches/bycode/kr/manifest" | grep -v ' PhoneProjection ' | grep -v ' file ' > "$HP/patches/bycode/krp/manifest"
    cp "$HP/patches/bycode/kr/"*.lpd "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/krp/"
    echo "3_bridge app PhoneProjection 0123456789abcdef0123456789abcdef bycode/krp/PhoneProjection.bridge.lpd 0123456789abcdef0123456789abcdef" >> "$HP/patches/bycode/krp/manifest"
    grep -v ' PhoneProjection ' "$HP/patches/bycode/krp/manifest" > "$HP/patches/bycode/kri/manifest"
    echo "FAKELPD $pp PhoneProjection-bridge" > "$HP/patches/bycode/kri/PhoneProjection.bridge.lpd"
    echo "3_bridge app PhoneProjection $pp bycode/kri/PhoneProjection.bridge.lpd $(want_file PhoneProjection-bridge)" >> "$HP/patches/bycode/kri/manifest"
    cp "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/kri/"
    sed -i '' 's/^\(2_tbt app HKMC_GPM\) [0-9a-f]*/\1 0123456789abcdef0123456789abcdef/' "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.10): kri (Ioniq 6) with both parts over krp (turn-by-turn only) and kr (nothing)" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = kri ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "by code: kri: PhoneProjection, DiPO and Iap2 their bridge builds, GPM and Navi patched" eval 'grep -q "dex PhoneProjection-bridge" "$ROOT/system/app/PhoneProjection.apk" && grep -q "dex HKMC_DiPO-bridge" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex Iap2ServerApp-bridge" "$ROOT/system/app/Iap2ServerApp.apk" && grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && grep -q "dex HKMC_Navi_ExSL-tbt" "$ROOT/system/app/HKMC_Navi_ExSL.apk"'
    check "by code: kri: no library line, the library stays stock" same_file "$ROOT/stock/libautoreceiver_infobank.so" "$ROOT/system/lib/libautoreceiver_infobank.so"
    check "by code: kri: the report names it" grep -q 'set auto (profile kri, parts 2_tbt 3_bridge)' "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-other-model-set.json"
)
(
    # 0.1.10 krg (Genesis G70 FL Korea IKFL): kr's lines plus its own PhoneProjection; kr, kra and krt (other
    # PhoneProjections) fit the turn-by-turn only: krg, between them by name, wins with both parts
    bycode_setup other
    pp=$(python3 -c "import struct,hashlib;d=open('$ROOT/stock/PhoneProjection.odex','rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())")
    for o in kra krt; do
        mkdir -p "$HP/patches/bycode/$o"
        grep -v ' PhoneProjection ' "$HP/patches/bycode/kr/manifest" > "$HP/patches/bycode/$o/manifest"
        echo "3_bridge app PhoneProjection 0123456789abcdef0123456789abcdef bycode/$o/PhoneProjection.bridge.lpd 0123456789abcdef0123456789abcdef" >> "$HP/patches/bycode/$o/manifest"
    done
    mkdir -p "$HP/patches/bycode/krg"
    grep -v ' PhoneProjection ' "$HP/patches/bycode/kr/manifest" > "$HP/patches/bycode/krg/manifest"
    echo "FAKELPD $pp PhoneProjection-g70bridge" > "$HP/patches/bycode/krg/PhoneProjection.bridge.lpd"
    echo "3_bridge app PhoneProjection $pp bycode/krg/PhoneProjection.bridge.lpd $(want_file PhoneProjection-g70bridge)" >> "$HP/patches/bycode/krg/manifest"
    cp "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/krg/"
    hook postinstall; rc=$?
    check "by code (0.1.10): krg (G70 FL) with both parts over kr, kra and krt (turn-by-turn only)" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = krg ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "by code: krg: PhoneProjection is its own bridge build, the library kr's" eval 'grep -q "dex PhoneProjection-g70bridge" "$ROOT/system/app/PhoneProjection.apk" && grep -q "dex lib-tbt" "$ROOT/system/lib/libautoreceiver_infobank.so"'
)
(
    # ... and the Ioniq 5 (its PhoneProjection is kr's): kr fits both parts, kra (another PhoneProjection) only one: kr
    bycode_setup same
    mkdir -p "$HP/patches/bycode/kra"
    grep -v ' PhoneProjection ' "$HP/patches/bycode/kr/manifest" > "$HP/patches/bycode/kra/manifest"
    echo "3_bridge app PhoneProjection 0123456789abcdef0123456789abcdef bycode/kra/PhoneProjection.bridge.lpd 0123456789abcdef0123456789abcdef" >> "$HP/patches/bycode/kra/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.6): an Ioniq 5 keeps kr with both parts next to kra" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/profile")" = kr ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ] && grep -q "dex PhoneProjection-bridge" "$ROOT/system/app/PhoneProjection.apk"'
)
(
    bycode_setup other
    CODESUM_HANG=1 hook postinstall; rc=$?
    check "by code: the helper does not answer: locked (no auto set), exit 0" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ]'
)

# ---------------------------------------------------------------- failures put the stock files back
(
    setup
    echo "FAKELPD 0123456789abcdef0123456789abcdef dipo-bridge" > "$HP/patches/neev_kr/HKMC_DiPO.bridge.lpd"
    snap "$ROOT/before"
    hook postinstall; rc=$?
    snap "$ROOT/after"
    check "build fails: exit 1" [ $rc -eq 1 ]
    check "build fails: state=failed, reason names HKMC_DiPO" eval '[ "$(st state)" = failed ] && case "$(st reason)" in *HKMC_DiPO*) true ;; *) false ;; esac'
    check "build fails: /system unchanged" cmp -s "$ROOT/before" "$ROOT/after"
    check "build fails: not marked installed" [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud/installed" ]
)
(
    setup
    chmod 0555 "$ROOT/system/lib"   # the receiver library (third target) cannot be written
    hook postinstall; rc=$?
    chmod 0755 "$ROOT/system/lib"
    check "write fails half way: exit 1" [ $rc -eq 1 ]
    check "write fails: state=failed, the stock files are back" eval '[ "$(st state)" = failed ] && case "$(st reason)" in *"stock files are back"*) true ;; *) false ;; esac'
    check "write fails: every stock file byte-identical" all_stock
    check "write fails: apps started again" [ "$(grep -c '^pm disable' "$ROOT/pm.log")" -eq "$(grep -c '^pm enable' "$ROOT/pm.log")" ]
)
(
    setup
    export DEXOPT_FAIL=1
    hook postinstall; rc=$?
    unset DEXOPT_FAIL
    check "dexopt fails: install still exit 0" [ $rc -eq 0 ]
    check "dexopt fails: no odex, the boot optimises" eval '[ ! -e "$ROOT/system/app/HKMC_GPM.odex" ] && grep -q "boot will optimise" "$ROOT/postinstall.out"'
    hook preuninstall; rc=$?
    check "dexopt fails: uninstall puts the stock odex back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    setup
    hook postinstall
    echo "damaged" > "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_Navi_ExSL.odex"
    hook preuninstall; rc=$?
    check "damaged stock copy: uninstall refuses (exit 1)" [ $rc -eq 1 ]
    check "damaged stock copy: state=failed naming the file" eval '[ "$(st state)" = failed ] && case "$(st reason)" in *HKMC_Navi_ExSL.odex*) true ;; *) false ;; esac'
    check "damaged stock copy: the other stock copies stay" [ -s "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk" ]
    check "damaged stock copy: the others were put back" same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/system/app/HKMC_GPM.apk"
)

# ---------------------------------------------------------------- recipes
(
    setup
    printf '%s\n' "id carplay-utils-converter" "file /system/lib/libCarPlayUtils.so" "stock $(q "$ROOT/stock/libCarPlayUtils.so")" > "$HP/recipes/carplay-utils-converter.recipe"
    hook postinstall; rc=$?
    check "utils fits: exit 0, the converter added" eval '[ $rc -eq 0 ] && [ "$(q "$ROOT/system/lib/libev6aac.so")" = badc26bd4c40a1c3e543b733a8ec5028 ]'
    check "utils fits: libCarPlayUtils patched" [ "$(tail -n 1 "$ROOT/system/lib/libCarPlayUtils.so")" = "patched carplay-utils-converter" ]
    check "utils fits: patched lists utils and conv" eval 'case ",$(st patched)," in *,utils,*conv,*|*,conv,*utils,*) true ;; *) false ;; esac'
    hook preuninstall; rc=$?
    check "utils fits: uninstall restores utils and removes the converter" eval '[ $rc -eq 0 ] && all_stock'
)
(
    setup
    printf '%s\n' "id carplay-utils-converter" "file /system/lib/libCarPlayUtils.so" "stock $(q "$ROOT/stock/libCarPlayUtils.so")" > "$HP/recipes/carplay-utils-converter.recipe"
    echo "someone's converter" > "$ROOT/system/lib/libev6aac.so"
    hook postinstall
    check "utils fits but libev6aac.so is someone else's: utils skipped" same_file "$ROOT/stock/libCarPlayUtils.so" "$ROOT/system/lib/libCarPlayUtils.so"
    check "... and their libev6aac.so untouched" [ "$(cat "$ROOT/system/lib/libev6aac.so")" = "someone's converter" ]
)
(
    setup
    echo "another firmware's audio" > "$ROOT/system/lib/libCarPlayAudio.so"
    hook postinstall; rc=$?
    check "audio recipe does not fit: install goes on (exit 0, reboot)" eval '[ $rc -eq 0 ] && [ "$(st state)" = reboot ]'
    check "audio recipe does not fit: the library untouched, not recorded" eval '[ "$(cat "$ROOT/system/lib/libCarPlayAudio.so")" = "another firmware'"'"'s audio" ] && ! grep -q libCarPlayAudio "$ROOT/data/nemesis/jmk-autoplay-hud/stock"'
)
(
    setup
    { cat "$ROOT/stock/libCarPlayAudio.so"; echo "patched carplay-audio-formats"; } > "$ROOT/system/lib/libCarPlayAudio.so"   # Leafia left it
    hook postinstall
    check "audio patched by something else: left alone, not ours" eval 'grep -q "patched by something else" "$ROOT/postinstall.out" && ! grep -q libCarPlayAudio "$ROOT/data/nemesis/jmk-autoplay-hud/stock"'
    check "audio patched by something else: not in patched" eval 'case ",$(st patched)," in *,audio,*) false ;; *) true ;; esac'
)

# ---------------------------------------------------------------- 0.1.8 (QA 2026-11-19)
setfp() { sed -i '' "s#^ro.build.fingerprint=.*#ro.build.fingerprint=$1#" "$PROPFILE"; }
newboot() { echo "boot-$1" > "$ROOT/proc/sys/kernel/random/boot_id"; }
# a firmware update: new stock files for GPM (apk + odex) and the receiver library, a new fingerprint
fw_update() {
    echo "new firmware HKMC_GPM.apk" > "$ROOT/system/app/HKMC_GPM.apk"; echo "new firmware HKMC_GPM.odex" > "$ROOT/system/app/HKMC_GPM.odex"
    echo "new firmware lib" > "$ROOT/system/lib/libautoreceiver_infobank.so"
    setfp "hyundai/neev_kr/neev:4.4.2/V040/270101:user/release-keys"
}
(
    setup
    hook postinstall
    check "0.1.8 install: the fingerprint kept with the records" grep -q 'V039/260902' "$S/fingerprint"
    newboot 2; svc
    check "0.1.8 next boot: active" [ "$(st state)" = active ]
    newboot 3; svc
    check "0.1.8 another boot, all in place: stays active" [ "$(st state)" = active ]
    fw_update
    mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"
    newboot 4; svc
    check "0.1.8 boot after a firmware update: failed, said in words" eval '[ "$(st state)" = failed ] && case "$(st reason)" in 펌웨어가*) true ;; *) false ;; esac'
    check "0.1.8 ... and reported" grep -q 'V039/260902:user/release-keys -> hyundai/neev_kr/neev:4.4.2/V040' "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-boot-firmware-changed.json"
    check "0.1.8 ... the replaced files' records and stock copies dropped" eval '! grep -q "^HKMC_GPM\.\|^libautoreceiver" "$S/stock" && [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex" ]'
    check "0.1.8 ... the fingerprint is the new firmware's" grep -q 'V040/270101' "$S/fingerprint"
    hook preuninstall; rc=$?
    check "0.1.8 uninstall after a firmware update: exit 0" [ $rc -eq 0 ]
    check "0.1.8 ... the new firmware's GPM and library untouched" eval '[ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "new firmware HKMC_GPM.odex" ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.apk")" = "new firmware HKMC_GPM.apk" ] && [ "$(cat "$ROOT/system/lib/libautoreceiver_infobank.so")" = "new firmware lib" ]'
    check "0.1.8 ... the rest back to stock" eval 'same_file "$ROOT/stock/HKMC_DiPO.apk" "$ROOT/system/app/HKMC_DiPO.apk" && same_file "$ROOT/stock/HKMC_DiPO.odex" "$ROOT/system/app/HKMC_DiPO.odex" && same_file "$ROOT/stock/libCarPlayAudio.so" "$ROOT/system/lib/libCarPlayAudio.so"'
)
(
    # a firmware update the service has not seen yet (uninstalled before the next boot): still never over its files
    setup
    hook postinstall
    fw_update
    hook preuninstall; rc=$?
    check "0.1.8 uninstall right after a firmware update: exit 0, its files untouched" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "new firmware HKMC_GPM.odex" ] && [ "$(cat "$ROOT/system/lib/libautoreceiver_infobank.so")" = "new firmware lib" ]'
    check "0.1.8 ... logged as left alone" grep -q 'left alone: .*HKMC_GPM.odex is not ours' "$ROOT/preuninstall.out"
    check "0.1.8 ... the others back to stock" same_file "$ROOT/stock/HKMC_Navi_ExSL.odex" "$ROOT/system/app/HKMC_Navi_ExSL.odex"
)
(
    # an uninstall that stopped after the apk went back: its odex (ours) still follows, on the same firmware
    setup
    hook postinstall
    cp "$ROOT/stock/HKMC_GPM.apk" "$ROOT/system/app/HKMC_GPM.apk"
    hook preuninstall; rc=$?
    check "0.1.8 apk back already, odex ours, same firmware: the odex put back too" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # ... but on another firmware a stock apk with another odex is the new framework's odex: left alone
    setup
    hook postinstall
    cp "$ROOT/stock/HKMC_GPM.apk" "$ROOT/system/app/HKMC_GPM.apk"; echo "odex for the new framework" > "$ROOT/system/app/HKMC_GPM.odex"
    setfp "hyundai/neev_kr/neev:4.4.2/V040/270101:user/release-keys"
    hook preuninstall; rc=$?
    check "0.1.8 another firmware, stock apk, other odex: the odex left alone" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "odex for the new framework" ]'
)
(
    # the next install after a firmware update builds from the new firmware's files, never from the old copies
    setup
    hook postinstall
    fw_update
    hook postinstall; rc=$?
    check "0.1.8 install after a firmware update: the old copies gone, locked on the new files (the fake set has no V040)" eval '[ $rc -eq 0 ] && [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk" ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.apk")" = "new firmware HKMC_GPM.apk" ]'
    check "0.1.8 ... the other files the earlier install patched stay, said so (not 'locked, nothing changed')" eval '[ "$(st state)" = reboot ] && case "$(st reason)" in "patched by 0.1.14"*) true ;; *) false ;; esac && case "$(st patched)" in *dipo*) true ;; *) false ;; esac'
)
(
    setup
    hook postinstall
    stage_update; echo "/system/xbin/nemesis uninstall jmk-autoplay-hud" > "$ROOT/parent.cmdline"   # a stage left behind
    hook preuninstall; rc=$?
    check "0.1.8 stale stage, parent 'nemesis uninstall': a real uninstall" eval '[ $rc -eq 0 ] && all_stock && [ ! -e "$ROOT/data/nemesis/jmk-autoplay-hud" ]'
)
(
    setup
    hook postinstall
    snap "$ROOT/before"
    stage_update; echo "com.xwtk.nemesis.manager" > "$ROOT/parent.cmdline"   # a parent that names neither (NEMESIS Manager)
    hook preuninstall; rc=$?
    snap "$ROOT/after"
    check "0.1.8 parent names neither, package staged: an update (the stage decides), files and records stay" eval '[ $rc -eq 0 ] && cmp -s "$ROOT/before" "$ROOT/after" && [ -s "$S/applied" ]'
    rm -f "$ROOT/parent.cmdline"   # unreadable
    hook preuninstall; rc=$?
    check "0.1.8 parent unreadable, package staged: an update" eval '[ $rc -eq 0 ] && [ -s "$S/applied" ] && ! all_stock'
    unstage; echo "com.xwtk.nemesis.manager" > "$ROOT/parent.cmdline"
    hook preuninstall; rc=$?
    check "0.1.8 parent names neither, nothing staged: a real uninstall" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # an update whose set no longer names PhoneProjection: put back to stock, its records go, the rest stays
    setup
    hook postinstall
    newboot 2; svc
    grep -v ' PhoneProjection ' "$HP/patches/neev_kr/manifest" > "$ROOT/m" && mv "$ROOT/m" "$HP/patches/neev_kr/manifest"
    snap "$ROOT/before"
    stage_update; hook preuninstall; hook postinstall; rc=$?; unstage
    check "0.1.8 update without a target: exit 0, state=reboot" eval '[ $rc -eq 0 ] && [ "$(st state)" = reboot ]'
    check "0.1.8 ... PhoneProjection back to stock" eval 'same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk" && same_file "$ROOT/stock/PhoneProjection.odex" "$ROOT/system/app/PhoneProjection.odex"'
    check "0.1.8 ... its records and stock copies gone" eval '! grep -q PhoneProjection "$S/stock" "$S/applied" && [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud/PhoneProjection.apk" ]'
    check "0.1.8 ... the others still patched" eval '[ "$(st patched)" = "gpm,navi,lib,iap2,dipo,audio" ]'
    check "0.1.8 ... logged" grep -q 'no longer targeted: PhoneProjection.apk PhoneProjection.odex' "$ROOT/postinstall.out"
    hook preuninstall
    check "0.1.8 ... then an uninstall: all stock" all_stock
)
(
    # an update whose patches do not fit (another set's stock md5 for GPM): the earlier files stay, active, said so
    setup
    hook postinstall
    newboot 2; svc
    snap "$ROOT/before"
    while read -r f s; do [ "$f" = HKMC_GPM.apk ] && s=99999999999999999999999999999999; echo "$f $s"; done < "$HP/patches/neev_kr/stock" > "$ROOT/s" && mv "$ROOT/s" "$HP/patches/neev_kr/stock"
    stage_update; hook preuninstall; hook postinstall; rc=$?; unstage
    snap "$ROOT/after"
    check "0.1.8 update that does not fit: exit 0, nothing changed" eval '[ $rc -eq 0 ] && cmp -s "$ROOT/before" "$ROOT/after"'
    check "0.1.8 ... state stays active, 'patched by 0.1.8', not locked" eval '[ "$(st state)" = active ] && case "$(st reason)" in "patched by 0.1.14: this version changed nothing"*) true ;; *) false ;; esac'
    check "0.1.8 ... patched lists the live files, set the old one" eval '[ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ] && [ "$(st set)" = neev_kr ]'
)
(
    setup
    snap "$ROOT/before"
    export DF_FREE=100.0K
    hook postinstall; rc=$?
    unset DF_FREE
    snap "$ROOT/after"
    check "0.1.8 no room on /system: exit 1, failed with the numbers" eval '[ $rc -eq 1 ] && [ "$(st state)" = failed ] && case "$(st reason)" in *"has 100 KB free"*) true ;; *) false ;; esac'
    check "0.1.8 no room: /system unchanged, no app stopped" eval 'cmp -s "$ROOT/before" "$ROOT/after" && [ ! -s "$ROOT/pm.log" ]'
)
(
    setup
    echo "half a copy" > "$ROOT/system/app/HKMC_GPM.apk.jmkhud"; echo "half" > "$ROOT/system/lib/libCarPlayAudio.so.jmkhud"
    hook preinstall; hook postinstall
    check "0.1.8 copies a cut-off swap left are removed" eval '! ls "$ROOT"/system/app/*.jmkhud "$ROOT"/system/lib/*.jmkhud >/dev/null 2>&1'
    echo "half" > "$ROOT/system/app/HKMC_DiPO.apk.jmkhud"
    svc
    check "0.1.8 ... by the service at boot too" [ ! -e "$ROOT/system/app/HKMC_DiPO.apk.jmkhud" ]
)
(
    setup
    head -c 300000 /dev/zero | tr '\0' x > "$ROOT/data/nemesis/jmk-autoplay-hud.log"
    hook postinstall
    check "0.1.8 a log over 256 KB: kept as .old, a new one started" eval '[ -s "$ROOT/data/nemesis/jmk-autoplay-hud.log.old" ] && [ $(wc -c < "$ROOT/data/nemesis/jmk-autoplay-hud.log") -lt 100000 ]'
)
(
    # an active add-on whose file something changed, same firmware: failed, not "active" for good
    setup
    hook postinstall
    newboot 2; svc
    echo "someone's GPM" > "$ROOT/system/app/HKMC_GPM.apk"
    newboot 3; svc
    check "0.1.8 active, a patched file changed (same firmware): failed naming it" eval '[ "$(st state)" = failed ] && case "$(st reason)" in *HKMC_GPM.apk*) true ;; *) false ;; esac'
)

passed=$(grep -c '^ok$' "$RESULTS"); failed=$(grep -c '^fail$' "$RESULTS")
echo
if [ "$failed" -eq 0 ]; then echo "all $passed passed"; exit 0; fi
echo "$failed FAILED, $passed passed"; exit 1
