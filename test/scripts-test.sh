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
    # 0.1.24: the first "extract" run gives nothing at once (another run removed its output, PDILCGAW)
    if [ -n "$CODESUM_FLAKY" ] && [ "$3" = extract ] && [ ! -f "$JMK_HUD_TEST_ROOT/flaky.done" ]; then : > "$JMK_HUD_TEST_ROOT/flaky.done"; return 0; fi
    [ "$1 $2" = "/system/bin jmkhud.CodeSum" ] || return 1
    shift 2
    # 0.1.23: the test apks are text ("<stock>" then "dex <name>", the fake zipadd): their "classes.dex" is that last line
    if [ "$1" = apkdex ]; then
        local l; l=$(command tail -n 1 "$2" 2>/dev/null)
        case "$l" in "dex "*) echo "dex=$(printf '%s\n' "$l" | command md5 -q)"; return 0 ;; esac
    fi
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
    check "install: ver=0.2.1" [ "$(st ver)" = 0.2.1 ]
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
    # 0.1.20 bridge_products / 0.1.28 bridge_framework: the bridge only where the framework was seen
    bycode_setup same
    echo "bridge_products OTHER.KOR.0000.V039.001.260902" >> "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.20): another product, no framework line: turn-by-turn only" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = 2_tbt ]'
)
(
    bycode_setup same
    mkdir -p "$ROOT/system/framework"; echo res > "$ROOT/system/framework/framework-res.apk"; echo fw > "$ROOT/system/framework/framework.odex"
    echo "bridge_products OTHER.KOR.0000.V039.001.260902" >> "$HP/patches/bycode/kr/manifest"
    echo "bridge_framework framework-res.apk=$(q "$ROOT/system/framework/framework-res.apk") framework.odex=$(q "$ROOT/system/framework/framework.odex")" >> "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.28): another product on the framework seen: both parts" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "by code (0.1.28): ... and the log says so" grep -q "runs the framework seen" "$ROOT/data/nemesis/jmk-autoplay-hud.log"
)
(
    # 0.1.32: several bridge_framework lines are alternatives (325RLNAK: framework-res.apk of its own, the same resources.arsc)
    bycode_setup same
    mkdir -p "$ROOT/system/framework"; echo res > "$ROOT/system/framework/framework-res.apk"; echo fw > "$ROOT/system/framework/framework.odex"
    echo "bridge_products OTHER.KOR.0000.V039.001.260902" >> "$HP/patches/bycode/kr/manifest"
    echo "bridge_framework framework-res.apk=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee framework.odex=$(q "$ROOT/system/framework/framework.odex")" >> "$HP/patches/bycode/kr/manifest"
    echo "bridge_framework framework-res.apk=$(q "$ROOT/system/framework/framework-res.apk") framework.odex=$(q "$ROOT/system/framework/framework.odex")" >> "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.32): the second framework line fits: both parts, the log names that line" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ] && grep -q "runs the framework seen (framework-res.apk=$(q "$ROOT/system/framework/framework-res.apk")" "$ROOT/data/nemesis/jmk-autoplay-hud.log"'
)
(
    bycode_setup same
    mkdir -p "$ROOT/system/framework"; echo res > "$ROOT/system/framework/framework-res.apk"; echo fw > "$ROOT/system/framework/framework.odex"
    echo "bridge_products OTHER.KOR.0000.V039.001.260902" >> "$HP/patches/bycode/kr/manifest"
    echo "bridge_framework framework-res.apk=$(q "$ROOT/system/framework/framework-res.apk") framework.odex=ffffffffffffffffffffffffffffffff" >> "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "by code (0.1.28): one framework file differs: turn-by-turn only, named in the log" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = 2_tbt ] && grep -q "not the one seen: framework.odex=" "$ROOT/data/nemesis/jmk-autoplay-hud.log"'
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
    check "0.1.25 damaged stock copy, the archive's intact: uninstall puts every stock file back" eval '[ $rc -eq 0 ] && all_stock'
    check "0.1.25 ... says the archive's copy was used" grep -q "the archive's copy is used" "$ROOT/data/nemesis/jmk-autoplay-hud.log"
    check "0.1.25 ... the archive outlives the uninstall" eval 'same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud.stock/HKMC_GPM.apk.$(q "$ROOT/stock/HKMC_GPM.apk")"'
)
(
    setup
    hook postinstall
    echo "damaged" > "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_Navi_ExSL.odex"
    for f in "$ROOT"/data/nemesis/backups/jmk-autoplay-hud.stock/HKMC_Navi_ExSL.odex.*; do echo "damaged" > "$f"; done
    hook preuninstall; rc=$?
    check "damaged stock copy (the archive's too): uninstall refuses (exit 1)" [ $rc -eq 1 ]
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

# ---------------------------------------------------------------- 0.1.37: the frame-wait recipe (libCarPlayCore), gated by recipes/gates
# stub recipes: the fake frames recipe fits the fake stock core (PATCHABLE); the Wi-Fi recipe is NATIVE on it, as on KR 260902
frames_fake() {   # frames_fake <stock md5 the gate wants> <md5 the built file must have>
    printf '%s\n' "id carplay-core-frames-ef49c09b" "file /system/lib/libCarPlayCore.so" "stock $(q "$ROOT/stock/libCarPlayCore.so")" > "$HP/recipes/carplay-core-frames-ef49c09b.recipe"
    printf '%s\n' "# fake gates" "carplay-core-frames-ef49c09b $1 $2" > "$HP/recipes/gates"
}
core_frames_md5() { { cat "$ROOT/stock/libCarPlayCore.so"; echo "patched carplay-core-frames-ef49c09b"; } | md5 -q; }
(
    setup
    hook postinstall; rc=$?
    check "0.1.37 no frames recipe in the package: install goes on, the log says so, the core untouched" eval '[ $rc -eq 0 ] && grep -q "recipe carplay-core-frames-ef49c09b: not in the package, skipped" "$ROOT/postinstall.out" && same_file "$ROOT/stock/libCarPlayCore.so" "$ROOT/system/lib/libCarPlayCore.so"'
)
(
    setup
    frames_fake "$(q "$ROOT/stock/libCarPlayCore.so")" "$(core_frames_md5)"
    hook postinstall; rc=$?
    check "0.1.37 frames recipe, the stock md5 is the gate's: install exit 0, state=reboot" eval '[ $rc -eq 0 ] && [ "$(st state)" = reboot ]'
    check "0.1.37 ... libCarPlayCore patched by it, with the md5 the gate wants" eval '[ "$(tail -n 1 "$ROOT/system/lib/libCarPlayCore.so")" = "patched carplay-core-frames-ef49c09b" ] && [ "$(q "$ROOT/system/lib/libCarPlayCore.so")" = "$(core_frames_md5)" ]'
    check "0.1.37 ... the log names each step (stock build, built, OK)" eval 'grep -q "recipe carplay-core-frames-ef49c09b: libCarPlayCore.so is the stock build $(q "$ROOT/stock/libCarPlayCore.so"): it will be patched" "$ROOT/postinstall.out" && grep -q "built libCarPlayCore.so with recipe carplay-core-frames-ef49c09b" "$ROOT/postinstall.out" && grep -q "OK: .*libCarPlayCore.so patched with recipe carplay-core-frames-ef49c09b" "$ROOT/postinstall.out"'
    check "0.1.37 ... the Wi-Fi recipe is not applied (it says NATIVE on the stock file, as before)" eval 'grep -q "recipe carplay-core-wifi: this firmware.s libCarPlayCore.so does it already" "$ROOT/postinstall.out"'
    check "0.1.37 ... patched lists core" eval 'case ",$(st patched)," in *,core,*) true ;; *) false ;; esac'
    check "0.1.37 ... the stock core is kept byte-identical and listed" eval 'same_file "$ROOT/stock/libCarPlayCore.so" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/libCarPlayCore.so" && grep -q "^libCarPlayCore.so $(q "$ROOT/stock/libCarPlayCore.so")$" "$ROOT/data/nemesis/jmk-autoplay-hud/stock"'
    snap "$ROOT/frames-1"
    hook postinstall; rc=$?
    check "0.1.37 ... a second run: exit 0, the core is patched already (ours), the Wi-Fi recipe says the file carries our other recipe, nothing changes" eval '[ $rc -eq 0 ] && grep -q "recipe carplay-core-frames-ef49c09b: libCarPlayCore.so is patched already (ours)" "$ROOT/postinstall.out" && grep -q "recipe carplay-core-wifi: this firmware.s libCarPlayCore.so does it already (the file carries our other recipe)" "$ROOT/postinstall.out"'
    snap "$ROOT/frames-2"
    check "0.1.37 ... the second run left every file as it was" cmp -s "$ROOT/frames-1" "$ROOT/frames-2"
    hook preuninstall; rc=$?
    check "0.1.37 ... uninstall puts the stock libCarPlayCore back (every system file is stock)" eval '[ $rc -eq 0 ] && all_stock'
)
(
    setup
    frames_fake "00000000000000000000000000000000" "$(core_frames_md5)"
    hook postinstall; rc=$?
    check "0.1.37 frames recipe, the stock md5 is not the gate's: install goes on, skipped with the md5 in the log" eval '[ $rc -eq 0 ] && grep -q "recipe carplay-core-frames-ef49c09b: libCarPlayCore.so is not the stock build this recipe is for (md5 $(q "$ROOT/stock/libCarPlayCore.so"), it wants 00000000000000000000000000000000): skipped" "$ROOT/postinstall.out"'
    check "0.1.37 ... the core untouched and not recorded" eval 'same_file "$ROOT/stock/libCarPlayCore.so" "$ROOT/system/lib/libCarPlayCore.so" && ! grep -q libCarPlayCore "$ROOT/data/nemesis/jmk-autoplay-hud/stock"'
)
(
    setup
    frames_fake "$(q "$ROOT/stock/libCarPlayCore.so")" "11111111111111111111111111111111"
    hook postinstall; rc=$?
    check "0.1.37 frames recipe builds a file with another md5 than the gate's: not written, install goes on, a warning" eval '[ $rc -eq 0 ] && grep -q "not the 11111111111111111111111111111111 it must be: not written" "$ROOT/postinstall.out" && case "$(st warn)" in *"carplay-core-frames-ef49c09b did not build"*) true ;; *) false ;; esac'
    check "0.1.37 ... the core untouched" same_file "$ROOT/stock/libCarPlayCore.so" "$ROOT/system/lib/libCarPlayCore.so"
)
(
    setup
    frames_fake "$(q "$ROOT/stock/libCarPlayCore.so")" "$(core_frames_md5)"
    printf '%s\n' "id carplay-core-wifi" "file /system/lib/libCarPlayCore.so" "stock $(q "$ROOT/stock/libCarPlayCore.so")" > "$HP/recipes/carplay-core-wifi.recipe"   # both would fit
    hook postinstall; rc=$?
    check "0.1.37 two recipes fit the same file: the first (frames) writes it, the other is skipped for it, the log says so" eval '[ $rc -eq 0 ] && [ "$(tail -n 1 "$ROOT/system/lib/libCarPlayCore.so")" = "patched carplay-core-frames-ef49c09b" ] && grep -q "recipe carplay-core-wifi: libCarPlayCore.so is taken by another recipe of this run: skipped" "$ROOT/postinstall.out"'
    hook preuninstall
    check "0.1.37 ... uninstall: every system file is stock again" all_stock
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
    check "0.1.8 ... the other files the earlier install patched stay, said so (not 'locked, nothing changed')" eval '[ "$(st state)" = reboot ] && case "$(st reason)" in "patched by 0.2.1"*) true ;; *) false ;; esac && case "$(st patched)" in *dipo*) true ;; *) false ;; esac'
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
    check "0.1.8 ... state stays active, 'patched by 0.1.8', not locked" eval '[ "$(st state)" = active ] && case "$(st reason)" in "patched by 0.2.1: this version changed nothing"*) true ;; *) false ;; esac'
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

# ---------------------------------------------------------------- 0.1.38: firmware changed after the install (an .odex is ours by its own md5)
fwrep() { echo "$ROOT/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-firmware-changed.json"; }
fw_outbox() { mkdir -p "$ROOT/data/local/tmp/jmk-map-menu/outbox"; }
V040="hyundai/neev_kr/neev:4.4.2/V040/270101:user/release-keys"
(
    # our apk, the new firmware's odex (a framework change rewrote the odex only): an uninstall never writes the old odex over it
    setup
    hook postinstall
    fw_outbox
    echo "odex of the new firmware" > "$ROOT/system/app/HKMC_GPM.odex"
    setfp "$V040"
    hook preuninstall; rc=$?
    check "0.1.38 uninstall, our apk + the new firmware's odex: exit 0, the odex is not written over" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "odex of the new firmware" ]'
    check "0.1.38 ... logged as left alone, reported firmware-changed (left as it is)" eval 'grep -q "left alone: .*HKMC_GPM.odex is not ours" "$ROOT/preuninstall.out" && grep -q "left as it is: HKMC_GPM.odex" "$(fwrep)"'
    check "0.1.38 ... the files that are ours (the other apps, the library, the GPM apk) went back to stock" eval 'same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/system/app/HKMC_GPM.apk" && same_file "$ROOT/stock/HKMC_Navi_ExSL.odex" "$ROOT/system/app/HKMC_Navi_ExSL.odex" && same_file "$ROOT/stock/libCarPlayAudio.so" "$ROOT/system/lib/libCarPlayAudio.so"'
)
(
    # both new (apk and odex rewritten by the firmware): neither written, reported
    setup
    hook postinstall
    fw_outbox
    echo "apk of the new firmware" > "$ROOT/system/app/HKMC_GPM.apk"; echo "odex of the new firmware" > "$ROOT/system/app/HKMC_GPM.odex"
    setfp "$V040"
    hook preuninstall; rc=$?
    check "0.1.38 uninstall, apk and odex both the new firmware's: neither written, reported" eval '[ $rc -eq 0 ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.apk")" = "apk of the new firmware" ] && [ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "odex of the new firmware" ] && grep -q "left as it is: HKMC_GPM" "$(fwrep)"'
)
(
    # both ours, the fingerprint another (a property change, no file changed): put back as before
    setup
    hook postinstall
    fw_outbox
    setfp "$V040"
    hook preuninstall; rc=$?
    check "0.1.38 uninstall, apk and odex both ours (fingerprint changed, files not): every file back to stock, nothing reported" eval '[ $rc -eq 0 ] && all_stock && [ ! -e "$(fwrep)" ]'
)
(
    # the update (postinstall again): our apk + the new firmware's odex: the old odex is not written over it
    setup
    hook postinstall
    fw_outbox
    echo "odex of the new firmware" > "$ROOT/system/app/HKMC_GPM.odex"
    setfp "$V040"
    hook postinstall; rc=$?
    check "0.1.38 update, our apk + the new firmware's odex: the odex is not written over" eval '[ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "odex of the new firmware" ]'
    check "0.1.38 ... the old stock odex and its record dropped (logged), reported firmware-changed" eval 'grep -q "firmware changed: .*HKMC_GPM.odex is the new firmware.s: the old stock copy and its record dropped" "$ROOT/postinstall.out" && grep -q "left as it is: HKMC_GPM.odex" "$(fwrep)" && ! grep -q "^HKMC_GPM.odex " "$S/stock"'
)
(
    # the tamper lock before any reconcile (the service at a boot with the same boot id): our apk + the new firmware's odex
    setup
    hook postinstall
    newboot 2; svc
    fw_outbox
    echo "odex of the new firmware" > "$ROOT/system/app/HKMC_GPM.odex"
    setfp "$V040"
    mkdir -p "$ROOT/data/nemesis/jmk-updates"; printf '%s\n' lock=1 state=damaged text=locked > "$ROOT/data/nemesis/jmk-updates/integrity"
    svc
    check "0.1.38 lock hold, our apk + the new firmware's odex: the odex is not written over, the rest back to stock, locked" eval '[ "$(cat "$ROOT/system/app/HKMC_GPM.odex")" = "odex of the new firmware" ] && [ "$(st state)" = locked ] && same_file "$ROOT/stock/HKMC_Navi_ExSL.odex" "$ROOT/system/app/HKMC_Navi_ExSL.odex" && grep -q "left as it is: HKMC_GPM.odex" "$(fwrep)"'
)
(
    # the same firmware, our apk and an odex that is neither stock nor in the made list: as before, put back (the legacy rule stays for it)
    setup
    hook postinstall
    echo "an odex nobody recorded" > "$ROOT/system/app/HKMC_GPM.odex"
    hook preuninstall; rc=$?
    check "0.1.38 same firmware, our apk + an odex that is not in the made list: put back as before (all stock)" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # a missing odex has nothing to be written over: put back on any firmware
    setup
    hook postinstall
    rm -f "$ROOT/system/app/HKMC_GPM.odex"
    setfp "$V040"
    hook preuninstall; rc=$?
    check "0.1.38 another firmware, our apk, the odex missing: the stock odex put back (nothing to overwrite)" eval '[ $rc -eq 0 ] && same_file "$ROOT/stock/HKMC_GPM.odex" "$ROOT/system/app/HKMC_GPM.odex"'
)

# ---------------------------------------------------------------- 0.1.15 (DPPB5BHV, Kia EV6 Korea, 2026-11-20)
# The car's dexopt: a Dalvik odex whose dex is the car's own re-optimised code of the apk it was given, so the code in
# the odex we write is neither the stock code nor our result dex (on the cars: EV6 GPM 7df6b900, result b02ada70).
car_dexopt() {
    cat > "$ROOT/system/bin/dexopt" <<'EOF'
#!/bin/bash
[ -n "$DEXOPT_FAIL" ] && exit 1
[ "$1" = --preopt ] || exit 1
python3 -c "
import struct,sys
dex=b'dex\n035\0'+(b'optimised by this car '+open(sys.argv[1],'rb').read())*8
hdr=b'dey\n036\0'+struct.pack('<8I',40,len(dex),0,0,0,0,0,0)
open(sys.argv[2],'wb').write(hdr+dex+b'deps of this framework')" "$2" "$3"
EOF
    chmod 0755 "$ROOT/system/bin/dexopt"
}
codeof() { python3 -c "import struct,hashlib,sys;d=open(sys.argv[1],'rb').read();o,l=struct.unpack_from('<II',d,8);print(hashlib.md5(d[o:o+l]).hexdigest())" "$1"; }
upd() { stage_update; hook preuninstall; hook postinstall; UPD_RC=$?; unstage; }
OUTBOX_REL=data/local/tmp/jmk-map-menu/outbox
# putback_cut <file>: a put-back (an uninstall, a rollback, the tamper lock's) cut off right after that file: it and
# every file before it in STOCK_LIST order are stock again, the rest are as this package wrote them
putback_cut() {
    local f s d
    while read -r f s; do
        case "$f" in *.so) d=$ROOT/system/lib ;; *) d=$ROOT/system/app ;; esac
        cp "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$f" "$d/$f"
        [ "$f" = "$1" ] && break
    done < "$S/stock"
}
# newbuild <part> <app> <payload>: a later version of the kr profile, whose result for that line is another build
newbuild() {
    local c t=${1#*_}
    c=$(awk -v p="$1" -v n="$2" '$1 == p && $3 == n { print $4 }' "$HP/patches/bycode/kr/manifest")
    echo "FAKELPD $c $3" > "$HP/patches/bycode/kr/$2.$t.lpd"
    awk -v p="$1" -v n="$2" -v w="$(want_file "$3")" '$1 == p && $3 == n { $6 = w } { print }' "$HP/patches/bycode/kr/manifest" > "$ROOT/m" &&
        mv "$ROOT/m" "$HP/patches/bycode/kr/manifest"
}
copies_stock() {   # every app's stock copies in the backups are the stock files
    local a
    for a in $APPS; do
        same_file "$ROOT/stock/$a.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$a.apk" || return 1
        same_file "$ROOT/stock/$a.odex" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$a.odex" || return 1
    done
}
stock_only() {   # every line of the stock list and of the auto set's stock list is the true stock md5
    local l f s
    for l in "$S/stock" "$S/auto/stock"; do
        while read -r f s; do [ "$s" = "$(q "$ROOT/stock/$f")" ] || return 1; done < "$l"
    done
}
(
    # DPPB5BHV's sequence: an earlier version installed by code (0.1.8: profile kre, both parts), the next one an update
    # over it (0.1.9: everything in place; its report printed the live, patched code), then a put-back cut off right
    # after HKMC_DiPO.apk (its odex still the one our dexopt wrote, the files before it stock again), then a version with
    # a new DiPO bridge build (0.1.10): until 0.1.14 the update read the patched DiPO odex as the stock one, fitted no
    # profile and kept the earlier build (postinstall-kept-old "nor its code a profile"), on every later version too
    bycode_setup same; car_dexopt
    DIPO_STOCK=$(codeof "$ROOT/stock/HKMC_DiPO.odex")
    hook postinstall
    newboot 2; svc
    rm -f "$ROOT/data/nemesis/jmk-autoplay-hud.reported" "$ROOT/$OUTBOX_REL"/*   # the next version's reports
    upd
    R=$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-other-model-set.json
    check "0.1.15 an update over our own by-code files: in place" eval '[ $UPD_RC -eq 0 ] && grep -q "every target is in place already" "$ROOT/postinstall.out"'
    check "0.1.15 ... its report names the stock code the profile was chosen by, not the patched code in the live odex" \
        eval 'grep -q "HKMC_DiPO.code=$DIPO_STOCK" "$R" && ! grep -q "HKMC_DiPO.code=$(codeof "$ROOT/system/app/HKMC_DiPO.odex")" "$R"'
    putback_cut HKMC_DiPO.apk
    check "0.1.15 (the state: DiPO's apk stock, its odex ours, PhoneProjection patched)" eval 'same_file "$ROOT/stock/HKMC_DiPO.apk" "$ROOT/system/app/HKMC_DiPO.apk" && ! same_file "$ROOT/stock/HKMC_DiPO.odex" "$ROOT/system/app/HKMC_DiPO.odex" && grep -q "dex PhoneProjection-bridge" "$ROOT/system/app/PhoneProjection.apk"'
    newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    rm -f "$ROOT/data/nemesis/jmk-autoplay-hud.reported" "$ROOT/$OUTBOX_REL"/*
    upd
    check "0.1.15 DPPB5BHV: the next update rebuilds from the stock copies: exit 0, reboot, kr with both parts" \
        eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(st set)" = auto ] && [ "$(cat "$S/auto/profile")" = kr ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ]'
    check "0.1.15 ... not kept-old (before: postinstall-kept-old, nor its code a profile)" eval '! ls "$ROOT/$OUTBOX_REL"/*kept-old* >/dev/null 2>&1 && [ -z "$(st reason)" ]'
    check "0.1.15 ... DiPO is the new bridge build in its stock apk, with a new odex" eval '[ "$(cat "$ROOT/system/app/HKMC_DiPO.apk")" = "$(cat "$ROOT/stock/HKMC_DiPO.apk"; echo "dex HKMC_DiPO-bridge-v2")" ] && grep -q "optimised by this car" "$ROOT/system/app/HKMC_DiPO.odex"'
    check "0.1.15 ... every target patched again (GPM, Navi, the library and Iap2 rebuilt from their stock files)" [ "$(st patched)" = "gpm,navi,lib,dipo,iap2,pp,audio" ]
    check "0.1.15 ... the log: the code read from the stock copies (DiPO's stock code)" grep -q "by code: this car's stock code:.*HKMC_DiPO.code=$DIPO_STOCK" "$ROOT/data/nemesis/jmk-autoplay-hud.log"
    check "0.1.15 ... the stock copies are the stock files, both stock lists only stock md5s" eval 'stock_only && copies_stock'
    hook preuninstall; rc=$?
    check "0.1.15 ... then an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # the same with the cut right after HKMC_GPM.apk (an app of the turn-by-turn part only): before 0.1.15 the profile
    # fitted the bridge part only, and the update put GPM, Navi and the library back to stock (turn-by-turn lost)
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    upd
    putback_cut HKMC_GPM.apk
    newbuild 2_tbt HKMC_GPM HKMC_GPM-tbt-v2
    upd
    check "0.1.15 cut after HKMC_GPM.apk, then an update: both parts still, GPM the new build" eval '[ $UPD_RC -eq 0 ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ] && grep -q "dex HKMC_GPM-tbt-v2" "$ROOT/system/app/HKMC_GPM.apk"'
    check "0.1.15 ... turn-by-turn kept (Navi and the library patched, not put back)" eval '[ "$(st patched)" = "gpm,navi,lib,dipo,iap2,pp,audio" ] && stock_only'
)
(
    # a stock copy lost (HKMC_DiPO.apk gone from the backups): before 0.1.15 the update took our live, patched DiPO apk
    # for the stock one, recorded its md5 as stock and kept it as the "stock copy" (an uninstall would have put our
    # patched apk back as stock). Now nothing is built without a verified stock copy: the earlier files stay, said why.
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_DiPO.apk"
    newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    upd
    check "0.1.25 a stock copy lost, the archive's there: the update builds the new DiPO from it" eval '[ $UPD_RC -eq 0 ] && grep -q "dex HKMC_DiPO-bridge-v2" "$ROOT/system/app/HKMC_DiPO.apk" && [ "$(st patched)" = "gpm,navi,lib,dipo,iap2,pp,audio" ] && stock_only'
    check "0.1.25 ... the stock record still the stock md5" grep -qx "HKMC_DiPO.apk $(q "$ROOT/stock/HKMC_DiPO.apk")" "$S/stock"
)
(
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_DiPO.apk" "$ROOT"/data/nemesis/backups/jmk-autoplay-hud.stock/HKMC_DiPO.apk.*
    newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    rm -f "$ROOT/data/nemesis/jmk-autoplay-hud.reported"
    snap "$ROOT/before"
    upd
    snap "$ROOT/after"
    check "0.1.15 a stock copy lost (the archive's too): exit 0, nothing changed, the earlier build kept" eval '[ $UPD_RC -eq 0 ] && cmp -s "$ROOT/before" "$ROOT/after" && case "$(st reason)" in "patched by 0.2.1"*) true ;; *) false ;; esac'
    check "0.1.15 ... our patched DiPO apk never recorded or kept as the stock one" \
        eval 'grep -qx "HKMC_DiPO.apk $(q "$ROOT/stock/HKMC_DiPO.apk")" "$S/stock" && stock_only && [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_DiPO.apk" ]'
    check "0.1.15 ... the kept-old report says why (by code: kr: no stock copy of HKMC_DiPO)" grep -q 'by code: kr: no stock copy of HKMC_DiPO' "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-postinstall-kept-old.json"
)
(
    # the tamper lock's round trip (0.1.9): locked at a boot (every stock file back, the records gone), lifted at the next
    # (applied again as a fresh install), then an update with a new build: rebuilt from the stock copies
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    mkdir -p "$ROOT/data/nemesis/jmk-updates"
    printf '%s\n' lock=1 state=damaged text=locked > "$ROOT/data/nemesis/jmk-updates/integrity"
    newboot 3; svc
    check "0.1.15 tamper lock on: every stock file back, locked" eval 'all_stock && [ "$(st state)" = locked ]'
    printf '%s\n' lock=0 state=ok text= > "$ROOT/data/nemesis/jmk-updates/integrity"
    newboot 4; svc
    check "0.1.15 lock lifted: applied again, both parts" eval '[ "$(st state)" = reboot ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ] && [ "$(st patched)" = "gpm,navi,lib,dipo,iap2,pp,audio" ] && stock_only'
    newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    upd
    check "0.1.15 ... then an update: the new DiPO build from the stock copies, the rest in place" eval '[ $UPD_RC -eq 0 ] && grep -q "dex HKMC_DiPO-bridge-v2" "$ROOT/system/app/HKMC_DiPO.apk" && [ "$(st patched)" = "gpm,navi,lib,dipo,iap2,pp,audio" ] && stock_only'
    hook preuninstall; rc=$?
    check "0.1.15 ... and an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
# 0.1.15: kre loses its receiver-library line (DPPB5BHV: Android Auto drops with Naver Map; the owner's call). A car an
# earlier version patched with it gets the stock library back on the update (from its stock copy, ownership-checked),
# the other targets rebuilt; a fresh install leaves the library stock.
nolib() { grep -v '^2_tbt file libautoreceiver_infobank.so ' "$HP/patches/bycode/kr/manifest" > "$ROOT/m" && mv "$ROOT/m" "$HP/patches/bycode/kr/manifest"; }
(
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    check "0.1.15 library line dropped: (the earlier version patched the library)" grep -q "dex lib-tbt" "$ROOT/system/lib/libautoreceiver_infobank.so"
    nolib; newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    upd
    check "0.1.15 library line dropped, the update: exit 0, reboot, both parts" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ]'
    check "0.1.15 ... the library is the stock one again" same_file "$ROOT/stock/libautoreceiver_infobank.so" "$ROOT/system/lib/libautoreceiver_infobank.so"
    check "0.1.15 ... said so, its records and stock copy gone" eval 'grep -q "no longer targeted: libautoreceiver_infobank.so" "$ROOT/postinstall.out" && ! grep -q libautoreceiver "$S/stock" "$S/applied" "$S/auto/stock" && [ ! -e "$ROOT/data/nemesis/backups/jmk-autoplay-hud/libautoreceiver_infobank.so" ]'
    check "0.1.15 ... the other targets rebuilt / in place (DiPO the new build), patched without lib" eval 'grep -q "dex HKMC_DiPO-bridge-v2" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && [ "$(st patched)" = "gpm,navi,dipo,iap2,pp,audio" ] && stock_only'
    newboot 3; svc
    check "0.1.15 ... the next boot: active" [ "$(st state)" = active ]
    hook preuninstall; rc=$?
    check "0.1.15 ... an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # both 0.1.15 changes on DPPB5BHV's state: the put-back cut after HKMC_DiPO.apk (the library before it, stock again
    # already), then the version without the library line and with a new DiPO build
    bycode_setup same; car_dexopt
    hook postinstall
    newboot 2; svc
    upd
    putback_cut HKMC_DiPO.apk
    nolib; newbuild 3_bridge HKMC_DiPO HKMC_DiPO-bridge-v2
    upd
    check "0.1.15 DPPB5BHV with the library line dropped: rebuilt from the stock copies, both parts, the library stock" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ] && same_file "$ROOT/stock/libautoreceiver_infobank.so" "$ROOT/system/lib/libautoreceiver_infobank.so"'
    check "0.1.15 ... DiPO the new build, every other target patched, no library record left" eval 'grep -q "dex HKMC_DiPO-bridge-v2" "$ROOT/system/app/HKMC_DiPO.apk" && [ "$(st patched)" = "gpm,navi,dipo,iap2,pp,audio" ] && ! grep -q libautoreceiver "$S/stock" "$S/applied" && stock_only'
)
(
    bycode_setup same; car_dexopt
    nolib
    hook postinstall; rc=$?
    check "0.1.15 a fresh install on a profile without the library line: both parts, the library stock" eval '[ $rc -eq 0 ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ] && same_file "$ROOT/stock/libautoreceiver_infobank.so" "$ROOT/system/lib/libautoreceiver_infobank.so" && ! grep -q libautoreceiver "$S/stock" && [ "$(st patched)" = "gpm,navi,dipo,iap2,pp,audio" ]'
)

# ---------------------------------------------------------------- 0.1.16 (V035.001.250507: krc, krd)
# The V035 profiles' shape: turn-by-turn only, no library line (another build of the library), and one line keyed to a
# delta another profile ships (krc's Iap2ServerApp: krv's, the same stock code). kr fits none of this car's code.
v035_setup() {
    bycode_setup other; car_dexopt
    mkdir -p "$HP/patches/bycode/krc"
    grep '^2_tbt app ' "$HP/patches/bycode/kr/manifest" | sed 's# bycode/kr/\(HKMC_[A-Za-z_]*\)# bycode/krc/\1#' > "$HP/patches/bycode/krc/manifest"
    cp "$HP/patches/bycode/kr/"HKMC_*.tbt.lpd "$HP/patches/bycode/kr/knobs" "$HP/patches/bycode/krc/"
    sed -i '' 's/^\(2_tbt app HKMC_GPM\) [0-9a-f]*/\1 0123456789abcdef0123456789abcdef/' "$HP/patches/bycode/kr/manifest"
}
(
    v035_setup
    check "0.1.16 (setup) krc: turn-by-turn lines only, Iap2ServerApp from kr's delta, no library line" eval '[ "$(awk "{print \$1}" "$HP/patches/bycode/krc/manifest" | sort -u)" = 2_tbt ] && grep -q " Iap2ServerApp .* bycode/kr/Iap2ServerApp.tbt.lpd " "$HP/patches/bycode/krc/manifest" && ! grep -q " file " "$HP/patches/bycode/krc/manifest"'
    snap "$ROOT/before"
    hook postinstall; rc=$?
    check "0.1.16 a V035-shaped profile: exit 0, set auto, profile krc, turn-by-turn only" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ] && [ "$(st state)" = reboot ] && [ "$(cat "$S/auto/profile")" = krc ] && [ "$(cat "$S/auto/parts")" = 2_tbt ]'
    check "0.1.16 ... GPM, DiPO, Navi and Iap2ServerApp (the other profile's delta) patched in their own apks" eval 'grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && grep -q "dex HKMC_DiPO-tbt" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex HKMC_Navi_ExSL-tbt" "$ROOT/system/app/HKMC_Navi_ExSL.apk" && [ "$(cat "$ROOT/system/app/Iap2ServerApp.apk")" = "$(cat "$ROOT/stock/Iap2ServerApp.apk"; echo "dex Iap2ServerApp-tbt")" ]'
    check "0.1.16 ... the library and PhoneProjection stay stock, neither recorded" eval 'same_file "$ROOT/stock/libautoreceiver_infobank.so" "$ROOT/system/lib/libautoreceiver_infobank.so" && same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk" && ! grep -q "libautoreceiver\|PhoneProjection" "$S/stock" "$S/auto/stock"'
    check "0.1.16 ... patched: the four apps and the audio recipe (no lib, no pp), the stock lists only stock md5s" eval '[ "$(st patched | tr , "\n" | sort | tr "\n" " ")" = "audio dipo gpm iap2 navi " ] && stock_only'
    check "0.1.16 ... the report names the profile and its stock code" grep -q 'set auto (profile krc, parts 2_tbt); product GL3HEV.KOR.0000.V039.001.260902; code .*HKMC_GPM.code=' "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-other-model-set.json"
    newboot 2; svc
    check "0.1.16 ... the next boot: active" [ "$(st state)" = active ]
    upd
    check "0.1.16 ... an update over it: every target in place (read from the stock copies)" eval '[ $UPD_RC -eq 0 ] && grep -q "every target is in place already" "$ROOT/postinstall.out" && [ "$(cat "$S/auto/profile")" = krc ]'
    hook preuninstall; rc=$?
    snap "$ROOT/after"
    check "0.1.16 ... an uninstall: every stock file back, no auto set" eval '[ $rc -eq 0 ] && all_stock && [ ! -e "$S/auto" ]'
)
(
    # the same car on a firmware whose library md5 is another again: still krc (no library line to miss)
    v035_setup
    echo "another build of the library" > "$ROOT/system/lib/libautoreceiver_infobank.so"; cp "$ROOT/system/lib/libautoreceiver_infobank.so" "$ROOT/stock/"
    hook postinstall; rc=$?
    check "0.1.16 a V035-shaped profile does not depend on the library: krc, turn-by-turn, the library untouched" eval '[ $rc -eq 0 ] && [ "$(cat "$S/auto/profile")" = krc ] && [ "$(cat "$S/auto/parts")" = 2_tbt ] && [ "$(cat "$ROOT/system/lib/libautoreceiver_infobank.so")" = "another build of the library" ]'
)

# ---------------------------------------------------------------- 0.1.17: the tamper lock holds through installs and updates
# Before, only the settings service read the lock (at its start: every stock file back, the records dropped, the mark
# integrity-locked written). An install or an update (NEMESIS, the MAP menu) while it said lock=1 was a fresh install over
# the stock files, and the service NEMESIS starts right after it saw the mark and did nothing: patched while locked.
LOCK_TEXT="파일 손상으로 정식 버전을 다시 설치하세요"
lockon() { mkdir -p "$ROOT/data/nemesis/jmk-updates"; printf '%s\n' lock=1 state=damaged "text=$LOCK_TEXT" > "$ROOT/data/nemesis/jmk-updates/integrity"; }
lockoff() { printf '%s\n' lock=0 state=ok text= > "$ROOT/data/nemesis/jmk-updates/integrity"; }
held() { all_stock && [ "$(st state)" = locked ] && [ "$(st reason)" = "$LOCK_TEXT" ] && [ -z "$(st patched)" ] && [ ! -e "$S/stock" ] && [ ! -e "$S/applied" ]; }
(
    setup
    hook postinstall
    newboot 2; svc
    lockon
    newboot 3; svc
    check "0.1.17 (the lock at a boot: every stock file back, locked)" held
    : > "$ROOT/pm.log"; : > "$ROOT/nemesis.log"
    upd
    check "0.1.17 an update while locked (nemesis install --update): exit 0, every stock file stays, still locked with the lock's text" eval '[ $UPD_RC -eq 0 ] && held'
    check "0.1.17 ... nothing built, no app stopped, no remount" eval '! grep -q "built \|took " "$ROOT/postinstall.out" && [ ! -s "$ROOT/pm.log" ] && [ ! -s "$ROOT/nemesis.log" ]'
    check "0.1.17 ... the status names this version" [ "$(st ver)" = "$(sed -n 's/^package-version=//p' "$HP/NEMESIS.data")" ]
    svc
    check "0.1.17 ... the service NEMESIS starts after the update: still stock, locked" held
    newboot 4; svc
    check "0.1.17 ... the next boot: still stock, locked" held
    echo "/system/xbin/nemesis install --update /data/local/tmp/jmk-updates/jmk-autoplay-hud.zip" > "$ROOT/parent.cmdline.map"
    stage_update; cp "$ROOT/parent.cmdline.map" "$ROOT/parent.cmdline"; hook preuninstall; hook postinstall; rc=$?; unstage
    check "0.1.17 ... an update the MAP menu runs: the same" eval '[ $rc -eq 0 ] && held'
    lockoff; newboot 5; svc
    check "0.1.17 lock lifted (the lock's own rule): applied again at the next start, the mark gone" eval '[ "$(st state)" = reboot ] && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ] && [ ! -e "$S/integrity-locked" ]'
    newboot 6; svc
    check "0.1.17 ... then active" [ "$(st state)" = active ]
)
(
    setup
    lockon
    hook postinstall; rc=$?
    check "0.1.17 a first install while locked: exit 0, nothing patched, locked with the lock's text" eval '[ $rc -eq 0 ] && held'
    svc
    check "0.1.17 ... the service: still locked" held
    lockoff; newboot 2; svc
    check "0.1.17 ... lifted: applied (a fresh install)" eval '[ "$(st state)" = reboot ] && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ]'
)
(
    # a car an earlier version (<= 0.1.16) patched again while locked: the mark there, our files live, records again
    setup
    hook postinstall
    newboot 2; svc
    lockon; : > "$S/integrity-locked"
    newboot 3; svc
    check "0.1.17 locked, the mark there, our files live (patched by an earlier update): the service puts them back" held
)
(
    setup
    hook postinstall
    newboot 2; svc
    lockon; : > "$S/integrity-locked"
    upd
    check "0.1.17 ... the same state, the update: every stock file back, locked" eval '[ $UPD_RC -eq 0 ] && held'
)
(
    # the lock lifted while installing (the MAP menu wrote lock=0, the service has not started since): applied, once
    setup
    hook postinstall
    newboot 2; svc
    lockon; newboot 3; svc
    lockoff
    upd
    check "0.1.17 an update after the lock was lifted: applied, the mark gone" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ] && [ ! -e "$S/integrity-locked" ]'
    svc
    check "0.1.17 ... the service then applies nothing again" eval '! grep -q "lock lifted" "$ROOT/svc.out" "$ROOT/data/nemesis/jmk-autoplay-hud.log" && [ "$(st state)" = reboot ]'
)
(
    # 0.1.32 (2SANOLLE, YBUJA4LP, ... six Ioniq 5 Korea cars, 2026-11-23): an update whose stock copies are only in the archive
    # ($BACKUP lost them): have_stock logged "brought back from the archive" on stdout inside $(src_of ...), the line became the
    # lpatch path (MISSING, "could not rebuild HKMC_GPM's code from HKMC_GPM.odex"). The update must build from the archive's copy.
    setup
    hook postinstall
    newboot 2; svc
    rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.odex"
    lpd neev_kr/HKMC_GPM.tbt.lpd HKMC_GPM.odex gpm-tbt-v2
    awk -v w="$(want_app HKMC_GPM gpm-tbt-v2)" '$3 == "HKMC_GPM" && $1 == "2_tbt" { $5 = w } { print }' "$HP/patches/neev_kr/manifest" > "$ROOT/m" && mv "$ROOT/m" "$HP/patches/neev_kr/manifest"
    upd
    check "0.1.32 fixed set, the stock copy only in the archive: the update builds the new GPM from it (exit 0)" eval '[ $UPD_RC -eq 0 ] && grep -q "dex gpm-tbt-v2" "$ROOT/system/app/HKMC_GPM.apk"'
    check "0.1.32 ... no 'could not rebuild' / 'could not assemble', the archive's copy brought back" eval '! grep -q "could not rebuild\|could not assemble" "$ROOT/data/nemesis/jmk-autoplay-hud.log" && grep -q "brought back from the archive" "$ROOT/data/nemesis/jmk-autoplay-hud.log"'
)
(
    # a put-back that fails (a stock copy damaged): records kept, not marked, tried again at the next start
    setup
    hook postinstall
    newboot 2; svc
    echo damaged > "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk"
    for f in "$ROOT"/data/nemesis/backups/jmk-autoplay-hud.stock/HKMC_GPM.apk.*; do echo damaged > "$f"; done   # 0.1.25: the archive's too
    lockon
    upd
    check "0.1.17 an update while locked, a stock copy damaged: exit 0, failed with the lock's text, records kept, no mark" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = failed ] && case "$(st reason)" in "$LOCK_TEXT"*) true ;; *) false ;; esac && [ -s "$S/stock" ] && [ ! -e "$S/integrity-locked" ]'
    cp "$ROOT/stock/HKMC_GPM.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk"
    newboot 3; svc
    check "0.1.17 ... the copy good again, the next boot: every stock file back, locked" held
)

# ---------------------------------------------------------------- 0.1.17: our own earlier builds the applied record does not name
# GMI6OZC2 (Ioniq 5 Korea, locked since 0.1.13/0.1.14): HKMC_GPM.apk 1c4bfdda, the neev_kr GPM build of 0.1.0-0.1.4,
# no applied line for it: "not the stock file", as if another tool had written it. patches/known (src/mkknown.py) lists
# every result an earlier version wrote; ours() counts those, so a verified stock copy rebuilds it.
known_from() { { echo "# results of earlier versions (test)"; grep -v '^libCarPlayAudio.so ' "$1"; } > "$HP/patches/known"; }
gpm_v2() {   # the next version: another GPM build
    lpd neev_kr/HKMC_GPM.tbt.lpd HKMC_GPM.odex gpm-tbt-v2
    G2=$(want_app HKMC_GPM gpm-tbt-v2)
    while read -r a b c d e; do [ "$c" = HKMC_GPM ] && e=$G2; echo "$a $b $c $d $e"; done < "$HP/patches/neev_kr/manifest" > "$ROOT/m" && mv "$ROOT/m" "$HP/patches/neev_kr/manifest"
}
(
    # the applied record lost GPM's line; GPM is an earlier version's build, its stock copy in the backups
    setup
    hook postinstall
    newboot 2; svc
    known_from "$S/applied"
    grep -v '^HKMC_GPM.apk ' "$S/applied" > "$ROOT/a" && mv "$ROOT/a" "$S/applied"
    gpm_v2
    upd
    check "0.1.17 GPM an earlier build of ours without an applied line, its stock copy kept: the update rebuilds it (before: kept-old, not the stock file)" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ -z "$(st reason)" ] && [ "$(q "$ROOT/system/app/HKMC_GPM.apk")" = "$G2" ]'
    check "0.1.17 ... from the verified stock copy, recorded, every target patched" eval 'grep -qx "HKMC_GPM.apk $G2" "$S/applied" && same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/HKMC_GPM.apk" && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ]'
    hook preuninstall; rc=$?
    check "0.1.17 ... then an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # the applied record lost every app and library line (the stock list and copies kept): this version's builds in
    # place are recorded again, the changed one rebuilt
    setup
    hook postinstall
    newboot 2; svc
    known_from "$S/applied"
    grep '^libCarPlayAudio.so ' "$S/applied" > "$ROOT/a" && mv "$ROOT/a" "$S/applied"
    gpm_v2
    upd
    check "0.1.17 every app line lost: GPM rebuilt, the builds in place recorded again, every target patched" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ] && [ "$(grep -c . "$S/applied")" -eq 7 ]'
    newboot 3; svc
    check "0.1.17 ... the next boot: active" [ "$(st state)" = active ]
    hook preuninstall; rc=$?
    check "0.1.17 ... an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # GMI6OZC2 itself: those builds live (Leafia KR's, byte for byte), no record and no stock copy of ours; Leafia's own
    # snapshot of GPM's stock apk still there
    setup
    hook postinstall
    known_from "$S/applied"
    # 0.1.25: nothing of ours either (no archive, made list or journal: Leafia's builds, never written by us)
    rm -rf "$S" "$ROOT/data/nemesis/backups/jmk-autoplay-hud" "$ROOT/data/nemesis/backups/jmk-autoplay-hud.stock" \
           "$ROOT/data/nemesis/jmk-autoplay-hud.made" "$ROOT/data/nemesis/jmk-autoplay-hud.journal"
    mkdir -p "$ROOT/$OUTBOX_REL" "$ROOT/data/nemesis/backup/projection.tbt"
    cp "$ROOT/stock/HKMC_GPM.apk" "$ROOT/data/nemesis/backup/projection.tbt/"
    gpm_v2
    snap "$ROOT/before"
    hook postinstall; rc=$?
    snap "$ROOT/after"
    check "0.1.17 GMI6OZC2: no stock copy of ours: locked as before, nothing changed" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ] && cmp -s "$ROOT/before" "$ROOT/after"'
    check "0.1.17 ... the reason: a build of this add-on without its stock copy (before: not the stock file)" eval 'case "$(st reason)" in "HKMC_GPM.apk is a build of this add-on (md5 "*") but its stock copy "*) true ;; *) false ;; esac'
    check "0.1.17 ... the report names Leafia's snapshot and the stock files in it" grep -q 'leafia snapshot projection.tbt:HKMC_GPM.apk' "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-postinstall-locked.json"
)

# ---------------------------------------------------------------- 0.1.24: an empty code answer is asked once more
(
    bycode_setup same
    CODESUM_FLAKY=1 hook postinstall; rc=$?
    check "0.1.24 the code helper's first extract gives nothing (PDILCGAW: kept 0.1.18's builds): asked again, set auto, both parts" eval '[ $rc -eq 0 ] && [ -f "$ROOT/flaky.done" ] && [ "$(st set)" = auto ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
)

# ---------------------------------------------------------------- 0.1.23: a by-code build in an apk whose md5 the record does not name
# GFQ4GE5F (Casper Korea, 2026-11-22): after an install cut off, HKMC_DiPO.apk held 0.1.22's bridge dex but its apk md5
# was not the applied one; the next version's uninstall took it for another tool's file, dropped its record and its
# stock copies, and every install since locked the car. ours() now asks the apk's classes.dex (patches/known
# "<name>.dex <md5>").
dex_known() {   # the by-code results of the kr profile as known "<App>.dex <md5>" lines
    local p k n c x w
    while read -r p k n c x w; do [ "$k" = app ] && echo "$n.dex $w"; done < "$HP/patches/bycode/kr/manifest" > "$HP/patches/known"
}
rewrap() {   # rewrap <apk>: another apk md5, the same dex inside (its last line)
    { echo "another zip layout"; cat "$1"; } > "$1.n" && mv "$1.n" "$1"
}
(
    bycode_setup same
    dex_known
    hook postinstall
    newboot 2; svc
    rewrap "$ROOT/system/app/HKMC_DiPO.apk"
    hook preuninstall; rc=$?
    check "0.1.23 a rewrapped by-code DiPO (dex ours, apk md5 not recorded): the uninstall puts it back (before: left alone, record and stock copy dropped)" eval '[ $rc -eq 0 ] && all_stock'
)
(
    bycode_setup same
    dex_known
    hook postinstall
    newboot 2; svc
    rewrap "$ROOT/system/app/HKMC_DiPO.apk"
    K=$(q "$ROOT/system/app/HKMC_DiPO.apk")
    # what the old put-back left (GFQ4GE5F): DiPO's records and stock copies gone, its odex gone, the rest stock again
    for f in HKMC_DiPO.apk HKMC_DiPO.odex; do
        grep -v "^$f " "$S/stock" > "$ROOT/x" && mv "$ROOT/x" "$S/stock"
        grep -v "^$f " "$S/applied" > "$ROOT/x" && mv "$ROOT/x" "$S/applied"
        rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$f"
    done
    rm -f "$ROOT/system/app/HKMC_DiPO.odex"
    hook preuninstall
    hook postinstall; rc=$?
    check "0.1.23 GFQ4GE5F: DiPO without any stock copy but exactly the bridge build: not locked, both parts (before: locked for good)" eval '[ $rc -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(cat "$ROOT/data/nemesis/jmk-autoplay-hud/auto/parts")" = "2_tbt 3_bridge" ]'
    check "0.1.23 ... DiPO kept as it is, the others patched again" eval '[ "$(q "$ROOT/system/app/HKMC_DiPO.apk")" = "$K" ] && grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && grep -q "dex Iap2ServerApp-bridge" "$ROOT/system/app/Iap2ServerApp.apk" && grep -q "dex PhoneProjection-bridge" "$ROOT/system/app/PhoneProjection.apk"'
    check "0.1.23 ... the warning says DiPO stays on an uninstall" eval 'case "$(st warn)" in *"HKMC_DiPO kept as this add-on'"'"'s build"*) true ;; *) false ;; esac'
    hook preuninstall; rc=$?
    check "0.1.23 ... an uninstall: the others stock, DiPO left as it is" eval '[ $rc -eq 0 ] && same_file "$ROOT/stock/HKMC_GPM.apk" "$ROOT/system/app/HKMC_GPM.apk" && same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk" && [ "$(q "$ROOT/system/app/HKMC_DiPO.apk")" = "$K" ]'
)
(
    # the same with a dex that is no result of ours: still locked
    bycode_setup same
    dex_known
    hook postinstall
    newboot 2; svc
    echo "dex someone-else" >> "$ROOT/system/app/HKMC_DiPO.apk"
    for f in HKMC_DiPO.apk HKMC_DiPO.odex; do
        grep -v "^$f " "$S/stock" > "$ROOT/x" && mv "$ROOT/x" "$S/stock"
        grep -v "^$f " "$S/applied" > "$ROOT/x" && mv "$ROOT/x" "$S/applied"
        rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$f"
    done
    rm -f "$ROOT/system/app/HKMC_DiPO.odex"
    hook preuninstall
    hook postinstall; rc=$?
    check "0.1.23 a foreign dex in DiPO and no stock copy: locked as before" eval '[ $rc -eq 0 ] && [ "$(st state)" = locked ]'
)

# ---------------------------------------------------------------- 0.1.26: a library with no stock copy, live exactly the build
(
    bycode_setup same
    dex_known
    hook postinstall
    newboot 2; svc
    L=libautoreceiver_infobank.so
    K=$(q "$ROOT/system/lib/$L")
    # VEBJD2LL: a full remove + reinstall left our built library live, its record and stock copies gone (archive too)
    grep -v "^$L " "$S/stock" > "$ROOT/x" && mv "$ROOT/x" "$S/stock"
    grep -v "^$L " "$S/applied" > "$ROOT/x" && mv "$ROOT/x" "$S/applied"
    rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$L" "$ROOT"/data/nemesis/backups/jmk-autoplay-hud.stock/$L.* "$ROOT/data/nemesis/jmk-autoplay-hud.made"
    echo "$L $K" >> "$HP/patches/known"   # as on the car: our build of it is a known result ("is ours but has no stock record")
    hook preuninstall
    hook postinstall; rc=$?
    check "0.1.26 the library without a stock copy but exactly the build: not locked, both parts (before: locked)" eval '[ $rc -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(cat "$S/auto/parts")" = "2_tbt 3_bridge" ]'
    check "0.1.26 ... the library kept as it is" [ "$(q "$ROOT/system/lib/$L")" = "$K" ]
    check "0.1.26 ... the warning says it stays on an uninstall" eval 'case "$(st warn)" in *"libautoreceiver_infobank.so kept as this add-on"*) true ;; *) false ;; esac'
)

(
    # VEBJD2LL's full picture: every app and the library ours and live, no record, no stock copy, no archive at all
    bycode_setup same
    dex_known
    hook postinstall
    newboot 2; svc
    L=libautoreceiver_infobank.so
    echo "$L $(q "$ROOT/system/lib/$L")" >> "$HP/patches/known"
    for f in $(cut -d" " -f1 "$S/stock"); do
        case "$f" in libCarPlay*) continue ;; esac
        grep -v "^$f " "$S/stock" > "$ROOT/x" && mv "$ROOT/x" "$S/stock"
        grep -v "^$f " "$S/applied" > "$ROOT/x" && mv "$ROOT/x" "$S/applied"
        rm -f "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$f"
    done
    rm -rf "$ROOT/data/nemesis/backups/jmk-autoplay-hud.stock" "$ROOT/data/nemesis/jmk-autoplay-hud.made"
    rm -f "$ROOT"/system/app/*.odex
    hook preuninstall
    hook postinstall; rc=$?
    check "0.1.26 every app and the library kept, no stock copy at all: not locked (before: 'no stock copy of:')" eval '[ $rc -eq 0 ] && case "$(st state)" in reboot|active) true ;; *) false ;; esac && [ -s "$S/auto/parts" ]'
)

# ---------------------------------------------------------------- 0.1.25: the journal, the made list, a cut-off swap
(
    setup
    mkdir -p "$ROOT/$OUTBOX_REL"
    hook postinstall
    J=$ROOT/data/nemesis/jmk-autoplay-hud.journal
    check "0.1.25 the journal has the run, begin and end" eval 'grep -q " begin postinstall 0.2.1" "$J" && grep -q " end postinstall rc=0" "$J"'
    check "0.1.25 every write's intent and result in the journal" eval '[ "$(grep -c " intent " "$J")" -ge 6 ] && [ "$(grep -c " wrote " "$J")" -ge 6 ]'
    check "0.1.25 the made list names our DiPO build" grep -q "^HKMC_DiPO.apk $(want_app HKMC_DiPO dipo-bridge)$" "$ROOT/data/nemesis/jmk-autoplay-hud.made"
    check "0.1.25 the made list never names a stock md5" eval '! grep -q " $(q "$ROOT/stock/HKMC_DiPO.apk")$" "$ROOT/data/nemesis/jmk-autoplay-hud.made"'
    check "0.1.25 every stock copy archived" [ "$(ls "$ROOT/data/nemesis/backups/jmk-autoplay-hud.stock" | grep -vc index)" -eq 12 ]
    # a swap cut off: begin and one intent, no wrote, no end; the state it left
    echo "20261122-230000 99999 begin postinstall 0.1.25" >> "$J"
    echo "20261122-230001 99999 intent HKMC_GPM.apk aaaa bbbb" >> "$J"
    sed -i '' 's/^state=.*/state=installing/' "$S/status"
    rm -f "$ROOT/data/nemesis/jmk-autoplay-hud.reported"
    newboot 2; svc
    check "0.1.25 the service sees the cut-off swap and runs the install again" grep -q "the last install was cut off during its swap" "$ROOT/data/nemesis/jmk-autoplay-hud.log"
    check "0.1.25 ... the cut-off run reported, naming the unconfirmed write" grep -q "HKMC_GPM.apk" "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-run-cut-off.json"
    check "0.1.25 ... the add-on in place again (reboot or active)" eval 'case "$(st state)" in reboot|active) true ;; *) false ;; esac && [ "$(st patched)" = "gpm,navi,lib,iap2,dipo,pp,audio" ]'
    hook preuninstall; rc=$?
    check "0.1.25 ... an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
    check "0.1.25 ... the archive, journal and made list stay" eval '[ -d "$ROOT/data/nemesis/backups/jmk-autoplay-hud.stock" ] && [ -s "$J" ] && [ -s "$ROOT/data/nemesis/jmk-autoplay-hud.made" ]'
)

# ---------------------------------------------------------------- 0.1.17: a superseded fixed set (dl3hev): our by-code builds first
# old_set_setup: the by-code car (GL3HEV: kr's code, PhoneProjection another code) whose stock files are also exactly a
# fixed set's, "old" in Leafia's dl3hev shape (2_tbt GPM, Navi, the library; 3_bridge Iap2ServerApp, DiPO), marked
# superseded. Before 0.1.17 the fixed set won (pick_set: its stock files match), so such cars kept Leafia's builds.
old_set_setup() {
    bycode_setup other; car_dexopt
    mkdir -p "$HP/patches/old"
    : > "$HP/patches/old/stock"
    for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
        echo "$a.apk $(q "$ROOT/stock/$a.apk")" >> "$HP/patches/old/stock"; echo "$a.odex $(q "$ROOT/stock/$a.odex")" >> "$HP/patches/old/stock"
    done
    echo "libautoreceiver_infobank.so $(q "$ROOT/stock/libautoreceiver_infobank.so")" >> "$HP/patches/old/stock"
    lpd old/HKMC_GPM.tbt.lpd HKMC_GPM.odex gpm-old
    lpd old/HKMC_Navi_ExSL.tbt.lpd HKMC_Navi_ExSL.odex navi-old
    lpd old/lib.tbt.lpd libautoreceiver_infobank.so lib-old
    lpd old/Iap2ServerApp.bridge.lpd Iap2ServerApp.odex iap2-old
    lpd old/HKMC_DiPO.bridge.lpd HKMC_DiPO.odex dipo-old
    {
        echo "2_tbt app HKMC_GPM old/HKMC_GPM.tbt.lpd $(want_app HKMC_GPM gpm-old)"
        echo "2_tbt app HKMC_Navi_ExSL old/HKMC_Navi_ExSL.tbt.lpd $(want_app HKMC_Navi_ExSL navi-old)"
        echo "2_tbt file libautoreceiver_infobank.so old/lib.tbt.lpd $(want_file lib-old)"
        echo "3_bridge app Iap2ServerApp old/Iap2ServerApp.bridge.lpd $(want_app Iap2ServerApp iap2-old)"
        echo "3_bridge app HKMC_DiPO old/HKMC_DiPO.bridge.lpd $(want_app HKMC_DiPO dipo-old)"
    } > "$HP/patches/old/manifest"
    echo "# test: Leafia's original build" > "$HP/patches/old/superseded"
}
ours_built() { grep -q "dex HKMC_GPM-tbt" "$ROOT/system/app/HKMC_GPM.apk" && grep -q "dex HKMC_DiPO-tbt" "$ROOT/system/app/HKMC_DiPO.apk" && grep -q "dex Iap2ServerApp-tbt" "$ROOT/system/app/Iap2ServerApp.apk" && grep -q "dex HKMC_Navi_ExSL-tbt" "$ROOT/system/app/HKMC_Navi_ExSL.apk" && grep -q "dex lib-tbt" "$ROOT/system/lib/libautoreceiver_infobank.so"; }
four_copies() { local a; for a in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do same_file "$ROOT/stock/$a.apk" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$a.apk" && same_file "$ROOT/stock/$a.odex" "$ROOT/data/nemesis/backups/jmk-autoplay-hud/$a.odex" || return 1; done; }
(
    old_set_setup
    hook postinstall; rc=$?
    check "0.1.17 superseded set: a first install takes the by-code profile (kr, turn-by-turn; PhoneProjection another code), not the set" eval '[ $rc -eq 0 ] && [ "$(st set)" = auto ] && [ "$(cat "$S/auto/profile")" = kr ] && [ "$(cat "$S/auto/parts")" = 2_tbt ]'
    check "0.1.17 ... our builds in the car's own apks, the profile's knobs, PhoneProjection stock" eval 'ours_built && [ "$(st knobs)" = log,lane_dist,cp_lanes ] && same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk"'
)
(
    old_set_setup
    mv "$HP/patches/old/superseded" "$ROOT/superseded"   # an earlier version: no marker
    hook postinstall
    check "0.1.17 (an earlier version: set old, Leafia's builds, no knobs)" eval '[ "$(st set)" = old ] && grep -q "dex dipo-old" "$ROOT/system/app/HKMC_DiPO.apk" && [ -z "$(st knobs)" ]'
    newboot 2; svc
    mv "$ROOT/superseded" "$HP/patches/old/superseded"
    rm -f "$ROOT/data/nemesis/jmk-autoplay-hud.reported" "$ROOT/$OUTBOX_REL"/*
    upd
    check "0.1.17 the update from the superseded set: our by-code builds (kr, turn-by-turn), every old build replaced" eval '[ $UPD_RC -eq 0 ] && [ "$(st state)" = reboot ] && [ "$(st set)" = auto ] && [ "$(cat "$S/auto/parts")" = 2_tbt ] && ours_built && [ -z "$(st reason)" ]'
    check "0.1.17 ... the code read from the verified stock copies (stock_copy), the stock lists only stock md5s, PhoneProjection untouched" eval 'stock_only && four_copies && same_file "$ROOT/stock/PhoneProjection.apk" "$ROOT/system/app/PhoneProjection.apk" && grep -q "by code: this car.s stock code:.*HKMC_DiPO.code=$(codeof "$ROOT/stock/HKMC_DiPO.odex")" "$ROOT/data/nemesis/jmk-autoplay-hud.log"'
    check "0.1.17 ... the report names the profile and the stock code, PhoneProjection's too" grep -q 'set auto (profile kr, parts 2_tbt); product GL3HEV.KOR.0000.V039.001.260902; code .*PhoneProjection.code=' "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-other-model-set.json"
    newboot 3; svc
    check "0.1.17 ... the next boot: active" [ "$(st state)" = active ]
    upd
    check "0.1.17 ... the next update: stays on the profile, in place" eval '[ $UPD_RC -eq 0 ] && [ "$(st set)" = auto ] && grep -q "every target is in place already" "$ROOT/postinstall.out"'
    hook preuninstall; rc=$?
    check "0.1.17 ... an uninstall: every stock file back" eval '[ $rc -eq 0 ] && all_stock'
)
(
    # no profile fits the car's code: the superseded set as before (the fallback), and the report says the code
    old_set_setup
    sed -i '' 's/^\(2_tbt app HKMC_GPM\) [0-9a-f]*/\1 0123456789abcdef0123456789abcdef/' "$HP/patches/bycode/kr/manifest"
    hook postinstall; rc=$?
    check "0.1.17 superseded set, no profile fits: the set (the fallback), its builds" eval '[ $rc -eq 0 ] && [ "$(st set)" = old ] && [ "$(st state)" = reboot ] && grep -q "dex dipo-old" "$ROOT/system/app/HKMC_DiPO.apk"'
    check "0.1.17 ... the report names the stock code it was read as" grep -q 'set old; product GL3HEV.KOR.0000.V039.001.260902; code .*HKMC_GPM.code=' "$ROOT/$OUTBOX_REL/jmk-autoplay-hud-install-other-model-set.json"
)

passed=$(grep -c '^ok$' "$RESULTS"); failed=$(grep -c '^fail$' "$RESULTS")
echo
if [ "$failed" -eq 0 ]; then echo "all $passed passed"; exit 0; fi
echo "$failed FAILED, $passed passed"; exit 1
