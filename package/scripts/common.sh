#!/system/bin/sh
# jmk-autoplay-hud ("JMK AutoPlay 확장 (HUD · 계기판 길안내)"): shared by the install hooks, the settings service
# and bin/status.sh. NEMESIS runs the hooks as root with the package folder as the current directory.
#
# A fork of the NEMESIS community package projection.tbt ("Turn-by-Turn Guidance for Phone Projection", AGPL-3.0; its
# comp/2_tbt/scripts/common.sh: snapshot, put beside + rename, dexopt, dalvik-cache, restore) as shipped inside HMG
# Leafia Plus 1.0.5, combined with HMG Leafia Plus's own GPL-3.0 work: the CarPlay Bluetooth bridge part
# (comp/3_bridge), the CarPlay Wi-Fi audio part (comp/4_audio), scripts/cars.sh, scripts/build.sh, scripts/lpatch.sh
# and apps_hold/apps_release of scripts/common.sh (combined under section 13 of both licences). What changed and why:
# NOTICE.md. Licence of this package: GNU Affero General Public License version 3 (LICENSE). No warranty.
#
# This head unit's shell is mksh with toolbox: single-digit fds only; no sed/head/tail/awk/printf/tr/stat; toolbox
# grep, md5, cmp, cp, mv exist. On this car /system is read-write after boot by design: this package never makes it
# read-only (it only asks NEMESIS for rw when it finds /system read-only).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
# a hook started over adb runs in adbd's session: a pulled cable or a host timeout must not stop it halfway
trap '' HUP INT PIPE

ID=jmk-autoplay-hud
# R: a sandbox root for test/scripts-test.sh on the Mac only. Empty on the car, where every path is the real one.
R=${JMK_HUD_TEST_ROOT:-}
PKG=${PKG:-.}
PATCHES=$PKG/patches
LPATCH=$PKG/tools/lpatch
STORE=$R/data/nemesis/$ID            # our state (root only); the status file the JMK MAP menu's daemon reads
STATUS=$STORE/status
INSTALLED=$STORE/installed          # there while installed: an update's preinstall knows it is one
SET_FILE=$STORE/set                 # the patch set this car uses
STOCK_LIST=$STORE/stock             # "<file> <stock md5>" for every stock copy in $BACKUP
APPLIED=$STORE/applied              # "<file> <md5>" of every file this package wrote into /system
BOOT_FILE=$STORE/boot               # the boot that wrote them: state=reboot until another boot
HOLD_FILE=$STORE/stopped            # apps stopped for the file swap, started again by every way out
WORK=$STORE/build                   # the rebuilt files, before they go into /system
AUTO=$STORE/auto                    # 0.1.4: the set the by-code build made for this car (stock, manifest, built/, profile)
BYCODE=$PATCHES/bycode              # 0.1.4: <profile>/manifest: patches keyed to the code inside each stock .odex
BACKUP=$R/data/nemesis/backups/$ID  # the stock copies, put back by a real uninstall
LOG=$R/data/nemesis/$ID.log
REPORTED=$R/data/nemesis/$ID.reported
CONF=$R/data/local/tmp/$ID/config   # written by the JMK MAP menu's daemon (key=value)
APP_DIR=$R/system/app
LIB_DIR=$R/system/lib
SYS_BIN=$R/system/bin
NEMESIS_BIN=$R/system/xbin/nemesis
# the apps whose files the swap replaces (HKMC_GPM, HKMC_DiPO, Iap2ServerApp, HKMC_Navi_ExSL, PhoneProjection)
HOLD_PKGS="com.google.android.projection.sink com.daudio.app.dipo com.tcc.iap2server com.mnsoft.navi com.daudio.app.phoneprojection"
RECIPES=$PKG/recipes
ADDED=$STORE/added                  # "<file> <md5>" of files this package added (libev6aac.so), removed by the uninstall
CONV_SUM=badc26bd4c40a1c3e543b733a8ec5028   # files/libev6aac.so (Leafia's converter, GPL-3.0)
# what dexopt builds against when the hook's environment has no BOOTCLASSPATH (the KOR 260902 firmware's own order)
DEXOPT_BCP=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
WARN=

log() { echo "$1"; mkdir -p "${LOG%/*}" 2>/dev/null; echo "$(date) $1" >> "$LOG" 2>/dev/null; true; }

pkg_version() {
    local l
    [ -r "$PKG/NEMESIS.data" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in package-version=*) echo "${l#package-version=}"; return 0 ;; esac
    done < "$PKG/NEMESIS.data"
    return 1
}
VER=$(pkg_version) || VER=unknown

md5of() { set -- $(md5 "$1" 2>/dev/null); echo "$1"; }

# Is $1 a whole line of file $2 (toolbox grep has no -x / -F)?
has_line() {
    local l
    [ -f "$2" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do [ "$l" = "$1" ] && return 0; done < "$2"
    return 1
}

# lookup <list> <file>: the md5 a "<file> <md5>" list holds for that file
lookup() {
    local f s
    [ -f "$1" ] || return 1
    while read -r f s || [ -n "$f" ]; do
        [ "$f" = "$2" ] && [ -n "$s" ] && { echo "$s"; return 0; }
    done < "$1"
    return 1
}

# record <list> <file> <md5>: one line per file (replaces an older one)
record() {
    local l tmp=$1.tmp
    : > "$tmp" || return 1
    if [ -f "$1" ]; then
        while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$2 "*) ;; *) echo "$l" >> "$tmp" ;; esac; done < "$1"
    fi
    echo "$2 $3" >> "$tmp" && mv "$tmp" "$1"
}

# ---------------------------------------------------------------- patch sets (Leafia's patches/ layout)
#   patches/cars              <ro.build.product prefix> <set> <car name>
#   patches/<set>/stock       <file> <md5 of the stock file>
#   patches/<set>/manifest    2_tbt <app|file> <name> <patch> <md5 of the rebuilt file>
#   patches/<set>/knobs       the menu config keys this set's builds read (ours; absent = none)
# 0.1.4: "auto" is the set the by-code build made for this car (in our state, so it outlives package updates)
set_dir() { if [ "$1" = auto ]; then echo "$AUTO"; else echo "$PATCHES/$1"; fi; }
set_ok() { local d; [ -n "$1" ] || return 1; d=$(set_dir "$1"); [ -s "$d/stock" ] && [ -s "$d/manifest" ]; }
stock_sum() { lookup "$(set_dir "$SET")/stock" "$1"; }

car_set() {
    local p pre set name
    p=$(getprop ro.build.product)
    [ -n "$p" ] && [ -f "$PATCHES/cars" ] || return 1
    while read -r pre set name || [ -n "$pre" ]; do
        case "$pre" in ''|'#'*) continue ;; esac
        case "$p" in "$pre"*) set_ok "$set" && { echo "$set"; return 0; } ;; esac
    done < "$PATCHES/cars"
    return 1
}

car_name() {
    local pre set name
    if [ "$1" = auto ]; then [ -f "$AUTO/profile" ] && read -r name < "$AUTO/profile" && echo "this car (code of the $name profile)"; return 0; fi
    [ -f "$PATCHES/cars" ] || return 1
    while read -r pre set name || [ -n "$pre" ]; do
        case "$pre" in ''|'#'*) continue ;; esac
        [ "$set" = "$1" ] && { echo "$name"; return 0; }
    done < "$PATCHES/cars"
    return 1
}

# TARGETS: what this car ends up with, as "kind|name|patch|md5|part" words (no subshell loops: mksh and bash differ
# there), in Leafia's order: the 2_tbt files first, then the 3_bridge ones. A 3_bridge line replaces the 2_tbt line of
# the same file: Leafia's bridge build of HKMC_DiPO / Iap2ServerApp is projection.tbt's code plus the bridge, and its
# patch starts from the same stock .odex (the source md5 in both .lpd headers is the stock one), so the end state is
# the file Leafia installs last, rebuilt here in one step. 1_projection, 4_audio's converter part, 5_menu and the Wi-Fi
# provider are not ours: jmk-autoplay turns the stock features on; the audio and core recipes are below.
load_targets() {
    local part kind name patch want bridged= tbt= br=
    TARGETS=
    set_ok "$SET" || return 1
    while read -r part kind name patch want || [ -n "$part" ]; do
        [ "$part" = 3_bridge ] && bridged="$bridged $name "
    done < "$(set_dir "$SET")/manifest"
    while read -r part kind name patch want || [ -n "$part" ]; do
        case "$kind" in app|file) ;; *) continue ;; esac
        [ -n "$want" ] || continue
        case "$part" in
            2_tbt) case "$bridged" in *" $name "*) continue ;; esac; tbt="$tbt $kind|$name|$patch|$want|$part" ;;
            3_bridge) br="$br $kind|$name|$patch|$want|$part" ;;
        esac
    done < "$(set_dir "$SET")/manifest"
    TARGETS="$tbt$br"
    [ -n "$TARGETS" ]
}
split_target() { local IFS='|'; set -- $1; T_KIND=$1; T_NAME=$2; T_PATCH=$3; T_WANT=$4; T_PART=$5; }
t_files() { case "$T_KIND" in app) echo "$T_NAME.apk $T_NAME.odex" ;; *) echo "$T_NAME" ;; esac; }
t_main() { case "$T_KIND" in app) echo "$T_NAME.apk" ;; *) echo "$T_NAME" ;; esac; }
live_of() { case "$1" in *.so) echo "$LIB_DIR/$1" ;; *) echo "$APP_DIR/$1" ;; esac; }
tag_of() {
    case "$1" in
        HKMC_GPM) echo gpm ;; HKMC_DiPO) echo dipo ;; Iap2ServerApp) echo iap2 ;; HKMC_Navi_ExSL) echo navi ;;
        PhoneProjection) echo pp ;; libautoreceiver_infobank.so) echo lib ;; libCarPlayAudio.so) echo audio ;;
        libCarPlayCore.so) echo core ;; libCarPlayUtils.so) echo utils ;; libev6aac.so) echo conv ;; *) echo "$1" ;;
    esac
}
app_names() {
    local t out=
    for t in $TARGETS; do split_target "$t"; [ "$T_KIND" = app ] && out="$out $T_NAME"; done
    echo $out
}

# Every stock file of the set matches this car's live files (the set for a product that patches/cars does not name).
set_matches() {
    local SET=$1 TARGETS t f s
    load_targets || return 1
    for t in $TARGETS; do
        split_target "$t"
        for f in $(t_files); do
            s=$(stock_sum "$f") || return 1
            [ "$(md5of "$(live_of "$f")")" = "$s" ] || return 1
        done
    done
    return 0
}

# 0.1.1: the live md5 of every file the sets name, for the locked report: tells which firmware's files this car has
# (a set for it can only come from that firmware's own stock files, so the report says which ones to look for).
live_sums() {
    local d f s seen= out=
    for d in "$PATCHES"/*/stock; do
        [ -f "$d" ] || continue
        while read -r f s || [ -n "$f" ]; do
            case "$f" in ''|'#'*) continue ;; esac
            case " $seen " in *" $f "*) continue ;; esac
            seen="$seen $f"
            s=$(md5of "$(live_of "$f")")
            out="$out $f=${s:-none}"
        done < "$d"
    done
    echo "${out# }"
}

# 0.1.3: "<App>.code=<md5>" for every app the sets name, from tools/codesum.jar (our own, src/jmkhud/CodeSum.java): the
# md5 of the dex inside the app's odex. That is the same on cars whose apps run the same code whatever their framework
# (gen5w-Evergreen keys its universal patches with it), so the locked report tells whether a set made from one car's
# code (Ioniq 5 Korea) fits this one. Empty when it cannot run; never more than about 20 s (the report waits for it).
# codesum <args>: the one line tools/codesum.jar prints, empty when it cannot run; never more than about 20 s
codesum() {
    local jar pid n out=
    jar=$(cd "$PKG" 2>/dev/null && pwd)/tools/codesum.jar
    [ -f "$jar" ] || return 0
    mkdir -p "$STORE" 2>/dev/null
    rm -f "$STORE/codesum.out"
    CLASSPATH=$jar app_process /system/bin jmkhud.CodeSum "$@" > "$STORE/codesum.out" 2>/dev/null &
    pid=$!
    n=0
    while kill -0 "$pid" 2>/dev/null && [ $n -lt 20 ]; do sleep 1; n=$((n + 1)); done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ -f "$STORE/codesum.out" ] && read -r out < "$STORE/codesum.out"
    rm -f "$STORE/codesum.out"
    echo "$out"
}
code_sums() {
    local d f s seen= args=
    for d in "$PATCHES"/*/stock; do
        [ -f "$d" ] || continue
        while read -r f s || [ -n "$f" ]; do
            case "$f" in *.odex) ;; *) continue ;; esac
            case " $seen " in *" $f "*) continue ;; esac
            seen="$seen $f"
            [ -f "$(live_of "$f")" ] && args="$args $(live_of "$f")"
        done < "$d"
    done
    [ -n "$args" ] || return 0
    codesum $args
}

# The set for this car: the one an earlier install used, else patches/cars by product, else the first set whose stock
# files are exactly this car's (the md5 gate below checks every file again either way).
pick_set() {
    local s d
    if [ -f "$SET_FILE" ]; then read -r s < "$SET_FILE"; set_ok "$s" && { echo "$s"; return 0; }; fi
    # 0.1.2: the product's set only when this car's files are that set's; else any set that has exactly them (a firmware
    # the cars list maps to an older set, e.g. a 260903 Ioniq 5 under "NEEV23.USA." before its own line), else the
    # product's set anyway (the md5 gate then locks it and the report names the live files)
    local named=
    named=$(car_set) && set_matches "$named" && { echo "$named"; return 0; }
    for d in "$PATCHES"/*; do
        s=${d##*/}
        set_ok "$s" || continue
        [ "$s" = "$named" ] && continue
        set_matches "$s" && { echo "$s"; return 0; }
    done
    [ -n "$named" ] && { echo "$named"; return 0; }
    return 1
}

# ---------------------------------------------------------------- by code (0.1.4)
# A set rebuilds each app's modified code from one car's exact stock .odex. An .odex is the app's dex plus a header with
# its framework's checksums, so a car whose app runs the same code has the same dex inside a different .odex.
# patches/bycode/<profile>/manifest keys the same patches to that dex (src/mkbycode.py; "us" is gen5w-Evergreen's
# universal list):
#   <part> app <App> <md5 of the dex inside the stock .odex> <patch> <md5 of the result dex>
#   <part> file <library> <md5 of the stock library> <patch> <md5 of the result>
# For a car no set fits, each part (2_tbt, 3_bridge) whose every line has this car's code is rebuilt from this car's
# own stock files: the code comes out of its .odex (tools/codesum.jar extract), lpatch rebuilds the modified code from
# it, that must have the line's md5 (so it is byte for byte the code the profile's car runs), and zipadd puts it into
# this car's own .apk. The results and this car's stock md5s become the set "auto" ($AUTO, the usual set layout,
# patch "prebuilt:<file>"), so the gate, the swap, the boot and the uninstall work as for any other set. A part with a
# line this car's code does not have is left out (kr on a K8 HEV Korea: turn-by-turn yes, its PhoneProjection differs);
# the profile that fits the most parts is used (0.1.6: kra has K8's PhoneProjection, so K8 gets the bridge too); no part
# fits = no auto set.

# the stock copy of a file before any set is known: our backup when the live file is ours, else the live file
plan_src() {
    local f=$1 live
    live=$(live_of "$f")
    if [ -f "$BACKUP/$f" ] && ours "$f" "$(md5of "$live")"; then echo "$BACKUP/$f"; else echo "$live"; fi
}

# the apps any profile names, once
bycode_apps() {
    local d p k n c x w out=" "
    for d in "$BYCODE"/*/manifest; do
        [ -f "$d" ] || continue
        while read -r p k n c x w || [ -n "$p" ]; do
            case "$p" in ''|'#'*) continue ;; esac
            [ "$k" = app ] || continue
            case "$out" in *" $n "*) ;; *) out="$out$n " ;; esac
        done < "$d"
    done
    echo $out
}

# bycode_part_fits <profile dir> <part> <" App.code=<md5> ..." of this car>: every line of the part matches
bycode_part_fits() {
    local p k n c x w any=
    while read -r p k n c x w || [ -n "$p" ]; do
        case "$p" in ''|'#'*) continue ;; esac
        [ "$p" = "$2" ] || continue
        any=1
        if [ "$k" = app ]; then
            case "$3" in *" $n.code=$c "*) ;; *) return 1 ;; esac
        else
            [ "$(md5of "$(plan_src "$n")")" = "$c" ] || return 1
        fi
    done < "$1/manifest"
    [ -n "$any" ]
}

# bycode_make <profile dir> <parts>: the auto set from this car's stock files; 1 (and $AUTO untouched) on any miss
bycode_make() {
    local dir=$1 parts=$2 new=$AUTO.new p k n c x w src apk got bridged= seen=" "
    # 0.1.5: an install that dropped lpatch's exec bit ran nothing here ("can't execute: Permission denied", K8 cars
    # 2026-11-17): the by-code build failed and the add-on stayed locked; the set path did this later only
    chmod 0755 "$LPATCH" 2>/dev/null
    rm -rf "$new"
    mkdir -p "$new/built" || return 1
    : > "$new/stock"; : > "$new/manifest"
    while read -r p k n c x w || [ -n "$p" ]; do
        case "$p" in 3_bridge) case " $parts " in *" 3_bridge "*) bridged="$bridged $n " ;; esac ;; esac
    done < "$dir/manifest"
    while read -r p k n c x w || [ -n "$p" ]; do
        case "$p" in ''|'#'*) continue ;; esac
        case " $parts " in *" $p "*) ;; *) continue ;; esac
        # the bridge build of an app is its turn-by-turn build plus the bridge: only that one when both parts fit
        [ "$p" = 2_tbt ] && case "$bridged" in *" $n "*) continue ;; esac
        if [ "$k" = app ]; then
            src=$(plan_src "$n.odex"); apk=$(plan_src "$n.apk")
            [ -f "$apk" ] || { echo "$(date) by code: no $n.apk" >> "$LOG"; rm -rf "$new"; return 1; }
            got=$(codesum extract "$src" "$new/code.dex")
            [ "$got" = "code=$c" ] || { echo "$(date) by code: $n's code is ${got#code=}, not $c" >> "$LOG"; rm -rf "$new"; return 1; }
            rm -f "$new/classes.dex"
            "$LPATCH" delta "$PATCHES/$x" "$new/code.dex" "$new/classes.dex" >> "$LOG" 2>&1 &&
                [ "$(md5of "$new/classes.dex")" = "$w" ] &&
                "$LPATCH" zipadd "$apk" "$new/classes.dex" "$new/built/$p.$n.apk" >> "$LOG" 2>&1 || {
                echo "$(date) by code: $n ($p) did not rebuild to the profile's code $w" >> "$LOG"; rm -rf "$new"; return 1; }
            rm -f "$new/code.dex" "$new/classes.dex"
            echo "$p app $n prebuilt:$p.$n.apk $(md5of "$new/built/$p.$n.apk")" >> "$new/manifest"
            case "$seen" in *" $n "*) ;; *)
                seen="$seen$n "
                echo "$n.apk $(md5of "$apk")" >> "$new/stock"
                echo "$n.odex $(md5of "$src")" >> "$new/stock" ;;
            esac
        else
            src=$(plan_src "$n")
            "$LPATCH" delta "$PATCHES/$x" "$src" "$new/built/$p.$n" >> "$LOG" 2>&1 && [ "$(md5of "$new/built/$p.$n")" = "$w" ] || {
                echo "$(date) by code: $n ($p) did not rebuild to $w" >> "$LOG"; rm -rf "$new"; return 1; }
            echo "$p file $n prebuilt:$p.$n $w" >> "$new/manifest"
            echo "$n $c" >> "$new/stock"
        fi
    done < "$dir/manifest"
    [ -f "$dir/knobs" ] && cp "$dir/knobs" "$new/knobs"
    echo "${dir##*/}" > "$new/profile"
    echo "${parts# }" > "$new/parts"
    getprop ro.build.product > "$new/product"
    rm -rf "$AUTO"
    mv "$new" "$AUTO"
}

# bycode_build: 0 and $AUTO made when a profile has a part this car's code fits (quiet: the caller logs)
bycode_build() {
    local n args= codes dir parts part
    [ -d "$BYCODE" ] || return 1
    for n in $(bycode_apps); do args="$args $(plan_src "$n.odex")"; done
    [ -n "$args" ] || return 1
    codes=" $(codesum $args) "
    echo "$(date) by code: this car's code:$codes" >> "$LOG"
    # the profile that fits the most parts wins (0.1.6): kra fits K8's turn-by-turn and bridge, kr its turn-by-turn only,
    # so the first profile that fits anything (kr, by name) would leave K8 without the bridge; equal counts keep the
    # name order. Both parts first, then one part.
    local want
    for want in 2 1; do
        for dir in "$BYCODE"/*; do
            [ -s "$dir/manifest" ] || continue
            parts=
            for part in 2_tbt 3_bridge; do bycode_part_fits "$dir" "$part" "$codes" && parts="$parts $part"; done
            set -- $parts
            [ $# -eq $want ] || continue
            bycode_make "$dir" "$parts" && return 0
        done
    done
    rm -rf "$AUTO"
    return 1
}

# set_fits <set>: every target of the set is this car's stock file, or ours with the stock copy in $BACKUP
set_fits() {
    local SET=$1 TARGETS t T_HOW REASON
    load_targets || return 1
    for t in $TARGETS; do split_target "$t"; check_target || return 1; done
    return 0
}

# ---------------------------------------------------------------- the stock md5 gate
# ours <file> <live md5>: this package wrote that file (an odex follows its apk: dexopt's output varies)
ours() {
    local f=$1 got=$2
    case "$f" in *.odex) f=${f%.odex}.apk; got=$(md5of "$(live_of "$f")") ;; esac
    [ -n "$got" ] && has_line "$f $got" "$APPLIED"
}

# check_target: T_HOW=done (this version's file is in place already) or build (the stock copies are at hand: live, or
# our backup when the live one is ours). Returns 1 with REASON when a file is neither stock nor ours.
check_target() {
    local f s got main
    main=$(t_main)
    for f in $(t_files); do
        stock_sum "$f" >/dev/null || { REASON="patch set $SET has no stock md5 for $f"; return 1; }
    done
    if [ "$(md5of "$(live_of "$main")")" = "$T_WANT" ]; then
        for f in $(t_files); do
            s=$(stock_sum "$f")
            [ "$(md5of "$BACKUP/$f")" = "$s" ] || { REASON="$f is patched already but its stock copy is not in $BACKUP"; return 1; }
        done
        T_HOW=done
        return 0
    fi
    for f in $(t_files); do
        s=$(stock_sum "$f")
        got=$(md5of "$(live_of "$f")")
        [ "$got" = "$s" ] && continue
        if [ "$(md5of "$BACKUP/$f")" = "$s" ] && ours "$f" "$got"; then continue; fi
        REASON="$f is not the stock file (md5 ${got:-missing}, want $s)"
        return 1
    done
    T_HOW=build
    return 0
}

# the stock copy of a file: our backup when it holds the stock file (the live one may be ours), else the live file
src_of() {
    local s
    s=$(stock_sum "$1")
    if [ "$(md5of "$BACKUP/$1")" = "$s" ]; then echo "$BACKUP/$1"; else live_of "$1"; fi
}

# build_target: Leafia's rebuild into $WORK. lpatch rebuilds the modified code only from the exact stock .odex (or
# .so) its patch names, and zipadd puts it into the car's own stock .apk; the result must have the manifest's md5.
build_target() {
    local out got
    mkdir -p "$WORK" || { REASON="cannot create $WORK"; return 1; }
    chmod 0755 "$LPATCH" 2>/dev/null
    case "$T_PATCH" in prebuilt:*)   # the auto set (0.1.4): built from this car's own stock files by bycode_make
        if [ "$T_KIND" = app ]; then out=$WORK/$T_NAME.apk; else out=$WORK/$T_NAME; fi
        cp "$AUTO/built/${T_PATCH#prebuilt:}" "$out" 2>/dev/null || { REASON="the by-code build of $T_NAME is gone"; return 1; }
        got=$(md5of "$out")
        [ "$got" = "$T_WANT" ] || { rm -f "$out"; REASON="by-code ${out##*/} has md5 ${got:-none}, want $T_WANT"; return 1; }
        log "took ${out##*/} from this car's by-code build ($T_WANT)"
        return 0 ;;
    esac
    case "$T_KIND" in
        app)
            out=$WORK/$T_NAME.apk
            rm -f "$WORK/classes.dex" "$out"
            if ! "$LPATCH" delta "$PATCHES/$T_PATCH" "$(src_of "$T_NAME.odex")" "$WORK/classes.dex" >> "$LOG" 2>&1; then
                rm -f "$WORK/classes.dex"; REASON="lpatch could not rebuild $T_NAME's code from $T_NAME.odex"; return 1
            fi
            if ! "$LPATCH" zipadd "$(src_of "$T_NAME.apk")" "$WORK/classes.dex" "$out" >> "$LOG" 2>&1; then
                rm -f "$WORK/classes.dex" "$out"; REASON="lpatch could not assemble $T_NAME.apk"; return 1
            fi
            rm -f "$WORK/classes.dex" ;;
        file)
            out=$WORK/$T_NAME
            rm -f "$out"
            if ! "$LPATCH" delta "$PATCHES/$T_PATCH" "$(src_of "$T_NAME")" "$out" >> "$LOG" 2>&1; then
                rm -f "$out"; REASON="lpatch could not rebuild $T_NAME"; return 1
            fi ;;
    esac
    got=$(md5of "$out")
    if [ "$got" != "$T_WANT" ]; then
        rm -f "$out"; REASON="rebuilt ${out##*/} has md5 ${got:-none}, want $T_WANT"; return 1
    fi
    log "built ${out##*/} from the stock files ($T_WANT)"
    return 0
}

# backup_file <file> [md5]: the stock copy into $BACKUP once (md5 checked: the set's stock md5, or the one given for a
# library a recipe found stock), and its md5 into STOCK_LIST
backup_file() {
    local s=$2 bak=$BACKUP/$1
    [ -n "$s" ] || s=$(stock_sum "$1") || { REASON="no stock md5 for $1"; return 1; }
    if [ "$(md5of "$bak")" != "$s" ]; then
        rm -f "$bak.tmp"
        if ! cp "$(live_of "$1")" "$bak.tmp" 2>/dev/null || [ "$(md5of "$bak.tmp")" != "$s" ] || ! mv "$bak.tmp" "$bak"; then
            rm -f "$bak.tmp"; REASON="could not keep a stock copy of $1 in $BACKUP"; return 1
        fi
        chmod 0600 "$bak"
        log "stock $1 kept in $BACKUP ($s)"
    fi
    record "$STOCK_LIST" "$1" "$s" || { REASON="could not record $1 in $STOCK_LIST"; return 1; }
}

# ---------------------------------------------------------------- /system
system_rw() {
    local dev mnt fs opts rest
    [ -r "$R/proc/mounts" ] || return 1
    while read -r dev mnt fs opts rest; do
        [ "$mnt" = /system ] || continue
        case ",$opts," in *,rw,*) return 0 ;; esac
        return 1
    done < "$R/proc/mounts"
    return 1
}

# /system writable: on this car it is rw after boot and stays so (toolbox mount is refused; only NEMESIS remounts)
system_writable() {
    system_rw && return 0
    log "/system is read-only: asking NEMESIS for read-write"
    "$NEMESIS_BIN" remount rw >/dev/null 2>&1
    system_rw
}

# put_file <src> <dst>: copy beside the target, then rename over it (a new inode: a running app keeps its old mapping;
# the observer of /system/app ignores the .jmkhud name)
put_file() {
    local tmp=$2.jmkhud
    rm -f "$tmp" 2>/dev/null
    cp "$1" "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    cmp "$1" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0644 "$tmp" 2>/dev/null
    chown 0.0 "$tmp" 2>/dev/null
    mv "$tmp" "$2" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    [ -x "$SYS_BIN/restorecon" ] && restorecon "$2" 2>/dev/null
    cmp "$1" "$2" >/dev/null 2>&1
}

# write_odex <apk> <odex>: optimise the new apk beside it, as the stock build did (failure: the boot optimises it)
write_odex() {
    [ -n "$BOOTCLASSPATH" ] || export BOOTCLASSPATH=$DEXOPT_BCP
    [ -x "$SYS_BIN/dexopt" ] || return 1
    "$SYS_BIN/dexopt" --preopt "$1" "$2" "m=y,u=n" >> "$LOG" 2>&1 || return 1
    [ -s "$2" ] || return 1
    chmod 0644 "$2" 2>/dev/null
    chown 0.0 "$2" 2>/dev/null
    [ -x "$SYS_BIN/restorecon" ] && restorecon "$2" 2>/dev/null
    return 0
}

# apply_target: the rebuilt file into /system (the md5 checked), recorded as ours; an app gets its odex rewritten
apply_target() {
    local live
    live=$(live_of "$(t_main)")
    put_file "$WORK/$(t_main)" "$live" || { REASON="could not write $live"; return 1; }
    [ "$(md5of "$live")" = "$T_WANT" ] || { REASON="$live does not have the rebuilt md5 after the write"; return 1; }
    record "$APPLIED" "$(t_main)" "$T_WANT"
    if [ "$T_KIND" = app ]; then
        rm -f "$APP_DIR/$T_NAME.odex" 2>/dev/null
        [ -f "$APP_DIR/$T_NAME.odex" ] && { REASON="could not delete $APP_DIR/$T_NAME.odex"; return 1; }
        if write_odex "$live" "$APP_DIR/$T_NAME.odex"; then
            log "OK: $T_NAME.apk patched, odex written"
        else
            rm -f "$APP_DIR/$T_NAME.odex" 2>/dev/null
            log "dexopt failed for $T_NAME.apk: the boot will optimise it"
        fi
    else
        log "OK: $live patched"
    fi
    return 0
}

# restore_files: every file in STOCK_LIST back to its stock copy (md5 checked); REASON names the first failure
restore_files() {
    local f s live bad=0
    [ -f "$STOCK_LIST" ] || return 0
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] && [ -n "$s" ] || continue
        live=$(live_of "$f")
        [ "$(md5of "$live")" = "$s" ] && continue
        if [ "$(md5of "$BACKUP/$f")" != "$s" ]; then
            [ -n "$REASON" ] || REASON="the stock copy of $f is missing or damaged in $BACKUP"
            bad=1; continue
        fi
        if put_file "$BACKUP/$f" "$live" && [ "$(md5of "$live")" = "$s" ]; then
            log "restored $f (stock $s)"
        else
            [ -n "$REASON" ] || REASON="could not put back $live"
            bad=1
        fi
    done < "$STOCK_LIST"
    return $bad
}

# ---------------------------------------------------------------- Leafia's lpatch recipes (the CarPlay libraries)
# recipes/<id>.recipe: byte-exact patches lpatch applies only when every original byte matches (it holds only hashes
# of the stock bytes and the new bytes). Each checks itself: PATCHABLE (the stock bytes: patched here), APPLIED
# (patched: ours when we recorded it), NATIVE (this firmware does it already; KR 260902's libCarPlayCore and
# libCarPlayUtils), anything else does not fit and is skipped. Leafia's order: the converter (libCarPlayUtils, which
# then needs libev6aac.so) first, then the audio formats, then the core.
RECIPE_IDS="carplay-utils-converter carplay-audio-formats carplay-core-wifi"
recipe_file() {   # the library a recipe names ("file /system/lib/<name>"), as a name in $LIB_DIR
    local k v rest
    [ -f "$RECIPES/$1.recipe" ] || return 1
    while read -r k v rest || [ -n "$k" ]; do [ "$k" = file ] && { echo "${v##*/}"; return 0; }; done < "$RECIPES/$1.recipe"
    return 1
}
lp_state() {   # lp_state <recipe id> <file>: PATCHABLE | APPLIED | NATIVE | MISMATCH | MISSING | ERROR
    local out w st=ERROR
    [ -f "$2" ] || { echo MISSING; return 0; }
    chmod 0755 "$LPATCH" 2>/dev/null
    out=$("$LPATCH" check "$RECIPES/$1.recipe" "$2" 2>&1)
    set -f
    for w in $out; do case "$w" in status=*) st=${w#status=} ;; esac; done
    set +f
    echo "$st"
}
conv_ok() {   # libev6aac.so is absent, or the one we added
    [ -e "$LIB_DIR/libev6aac.so" ] || return 0
    has_line "libev6aac.so $(md5of "$LIB_DIR/libev6aac.so")" "$ADDED"
}
# check_recipes: R_TODO = the recipes to apply now; the log says why each other one is left
check_recipes() {
    local id f st live
    R_TODO=
    for id in $RECIPE_IDS; do
        f=$(recipe_file "$id") || { log "recipe $id: not in the package, skipped"; continue; }
        live=$LIB_DIR/$f
        st=$(lp_state "$id" "$live")
        case "$st" in
            PATCHABLE)
                if [ "$id" = carplay-utils-converter ] && ! conv_ok; then
                    log "recipe $id: $f fits, but $LIB_DIR/libev6aac.so is not ours: skipped"; continue
                fi
                R_TODO="$R_TODO $id" ;;
            APPLIED)
                if has_line "$f $(md5of "$live")" "$APPLIED" && [ "$(md5of "$BACKUP/$f")" = "$(lookup "$STOCK_LIST" "$f")" ]; then
                    log "recipe $id: $f is patched already (ours)"
                else
                    log "recipe $id: $f is patched by something else and we have no stock copy: left alone"
                fi ;;
            NATIVE) log "recipe $id: this firmware's $f does it already: nothing to do" ;;
            *) log "recipe $id: $f does not fit this firmware ($st): skipped" ;;
        esac
    done
}
build_recipe() {   # build_recipe <id>: the patched copy into $WORK (lpatch writes it only when every byte matched)
    local f
    f=$(recipe_file "$1") || return 1
    mkdir -p "$WORK" || return 1
    rm -f "$WORK/$f"
    "$LPATCH" apply "$RECIPES/$1.recipe" "$LIB_DIR/$f" "$WORK/$f" >> "$LOG" 2>&1 && [ -s "$WORK/$f" ] &&
        [ "$(lp_state "$1" "$WORK/$f")" = APPLIED ] && { log "built $f with recipe $1"; return 0; }
    rm -f "$WORK/$f"
    return 1
}
apply_recipe() {   # apply_recipe <id>: (the converter first for the utils recipe) the copy into /system, checked
    local f live
    f=$(recipe_file "$1"); live=$LIB_DIR/$f
    if [ "$1" = carplay-utils-converter ] && [ ! -e "$LIB_DIR/libev6aac.so" ]; then
        put_file "$PKG/files/libev6aac.so" "$LIB_DIR/libev6aac.so" && [ "$(md5of "$LIB_DIR/libev6aac.so")" = "$CONV_SUM" ] ||
            { REASON="could not add $LIB_DIR/libev6aac.so"; return 1; }
        record "$ADDED" libev6aac.so "$CONV_SUM"
        log "OK: added libev6aac.so (the converter libCarPlayUtils forwards to)"
    fi
    put_file "$WORK/$f" "$live" || { REASON="could not write $live"; return 1; }
    [ "$(lp_state "$1" "$live")" = APPLIED ] || { REASON="$live does not check as patched after the write"; return 1; }
    record "$APPLIED" "$f" "$(md5of "$live")"
    log "OK: $live patched with recipe $1"
}
# remove_added: the files we added (libev6aac.so) go, when they are still ours
remove_added() {
    local f s live bad=0
    [ -f "$ADDED" ] || return 0
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        live=$(live_of "$f")
        [ -e "$live" ] || continue
        if [ "$(md5of "$live")" != "$s" ]; then log "WARNING: $live changed since we added it: left alone"; continue; fi
        rm -f "$live" 2>/dev/null
        if [ -e "$live" ]; then [ -n "$REASON" ] || REASON="could not remove $live"; bad=1; else log "removed $live"; fi
    done < "$ADDED"
    [ $bad -eq 0 ] && rm -f "$ADDED"
    return $bad
}

# ---------------------------------------------------------------- dalvik-cache (best effort)
# Root started over adb on this car has no capabilities (CapEff 0xc0): /data/dalvik-cache (system 0771) is closed to
# it, so entries can stay. Harmless: Dalvik checks each entry against its apk and rebuilds a stale one at boot, and a
# stock apk (no classes.dex) runs from the odex beside it. Never a reason to stop.
wipe_dalvik() {
    local d n e left=
    for d in "$R/data/dalvik-cache" "$R/data/dalvik-cache/arm" "$R/cache/dalvik-cache"; do
        [ -d "$d" ] || continue
        for n in $1; do
            for e in "$d"/*"@$n.apk@"*; do
                [ -e "$e" ] || continue
                rm -f "$e" 2>/dev/null
                [ -e "$e" ] && left="$left ${e##*/}"
            done
        done
    done
    if [ -n "$left" ]; then
        WARN="dalvik-cache entries left:$left"
        log "WARNING: could not remove$left from the dalvik-cache (root without capabilities, e.g. over adb); harmless: the boot rebuilds stale entries"
    fi
    return 0
}

# prefill_dalvik <name>: the boot would optimise our apk (it carries classes.dex) into the cache; the odex is that same
# file, so put it there now. Not possible without capabilities: the boot then optimises it once.
prefill_dalvik() {
    local odex=$APP_DIR/$1.odex cache=$R/data/dalvik-cache/system@app@$1.apk@classes.dex
    [ -s "$odex" ] && [ -d "${cache%/*}" ] || return 0
    rm -f "$cache.tmp" 2>/dev/null
    if cp "$odex" "$cache.tmp" 2>/dev/null && cmp "$odex" "$cache.tmp" >/dev/null 2>&1; then
        chmod 0644 "$cache.tmp" 2>/dev/null
        chown 1000.1000 "$cache.tmp" 2>/dev/null
        if mv "$cache.tmp" "$cache" 2>/dev/null; then
            [ -x "$SYS_BIN/restorecon" ] && restorecon "$cache" 2>/dev/null
            log "dalvik-cache filled for $1.apk"
            return 0
        fi
    fi
    rm -f "$cache.tmp" 2>/dev/null
    log "dalvik-cache not filled for $1.apk: the boot will optimise it"
    return 0
}

# ---------------------------------------------------------------- the apps during the swap (from Leafia's bundle)
# With Android up they are stopped (pm disable, which also keeps persistent apps from restarting), so none starts
# against half-changed files. The list stays in HOLD_FILE until apps_release starts them again; the settings service
# also does it at boot, so a run that died never leaves them stopped. With Android down there is nothing to stop.
android_up() { [ "$(getprop sys.boot_completed)" = 1 ]; }
pkg_enabled() {
    local l
    for l in $(pm list packages -e "$1" </dev/null 2>/dev/null); do [ "$l" = "package:$1" ] && return 0; done
    return 1
}
apps_hold() {
    local p
    android_up || return 0
    : >> "$HOLD_FILE" 2>/dev/null || { log "WARNING: cannot record stopped apps; not stopping them"; return 0; }
    for p in $HOLD_PKGS; do
        has_line "$p" "$HOLD_FILE" && continue   # stopped by an earlier run: stays on the list
        pkg_enabled "$p" || continue              # absent, or disabled by the owner: left as it is
        echo "$p" >> "$HOLD_FILE"
        if pm disable "$p" </dev/null >/dev/null 2>&1; then log "stopped $p for the file swap"; else log "WARNING: could not stop $p"; fi
    done
    return 0
}
apps_release() {
    local p list left=
    [ -f "$HOLD_FILE" ] || return 0
    android_up || { log "apps stopped by an earlier run stay stopped until Android is up"; return 0; }
    list=$(cat "$HOLD_FILE")
    for p in $list; do
        if pm enable "$p" </dev/null >/dev/null 2>&1; then log "started $p again"; else left="$left $p"; log "WARNING: could not start $p again (pm enable $p)"; fi
    done
    if [ -z "$left" ]; then rm -f "$HOLD_FILE"; else echo $left > "$HOLD_FILE"; fi
    return 0
}

# ---------------------------------------------------------------- packages around us
pkg_installed() { [ -d "$R/data/nemesis/apps/$1" ] || [ -d "$R/data/nemesis/packages/$1" ]; }

# Another phone-projection package changes the same stock apps: Leafia and its Korean port (wireless.cp.aa.*,
# leafia.*), the upstream NEMESIS community packages (wireless.carplay.aa, wireless.projection, projection.tbt,
# wireless.carplay.bt, carplay.*), Evergreen, 단풍 (danpung*), Korea Projection (korea.projection), aa.usbwifi, an
# HMG-API projection mod. Our own packages (jmk-*) never count. Prints the first one found.
other_projection() {
    local d id
    for d in "$R"/data/nemesis/apps/* "$R"/data/nemesis/packages/*; do
        [ -d "$d" ] || continue
        id=${d##*/}
        case "$id" in
            jmk-*|jmk.*) ;;
            wireless.*|*projection*|*carplay*|*androidauto*|*leafia*|*evergreen*|danpung*|aa.usbwifi|*.tbt|*.tbt.*)
                echo "$id"; return 0 ;;
        esac
    done
    for d in "$R"/data/hmgapi/mods/*; do
        [ -d "$d" ] || continue
        case "${d##*/}" in *wireless*|*carplay*|*projection*|*tbt*) echo "HMG-API mod ${d##*/}"; return 0 ;; esac
    done
    return 1
}

# NEMESIS runs the installed package's preuninstall before an update too, with the new package staged already; only
# a real uninstall (its parent says "uninstall") puts the stock files back.
is_update() {
    case "$(cat /proc/$PPID/cmdline 2>/dev/null)" in *uninstall*) return 1 ;; esac
    grep -q "^id=$ID\$" "$R/data/local/tmp/nemesis/stage/$ID/NEMESIS.data" 2>/dev/null
}

# One install report per version and category, through the JMK MAP menu's outbox (it sends them when online).
report() {
    local box=$R/data/local/tmp/jmk-map-menu/outbox detail=$2 tmp
    [ -d "$box" ] || return 0
    case "$1" in ''|*[!a-z0-9-]*) return 0 ;; esac
    case "$VER" in ''|*[!0-9.]*) return 0 ;; esac
    has_line "$VER $1" "$REPORTED" && return 0
    case "$detail" in *'"'*|*'\'*) detail='(detail not printable)' ;; esac
    tmp=$box/.$ID-install-$$.tmp
    echo "{\"kind\":\"jmk-report\",\"type\":\"install\",\"app\":\"$ID\",\"ver\":\"$VER\",\"msg\":\"install: $1\",\"detail\":\"$detail\",\"at\":$(date +%s)000}" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    chmod 0644 "$tmp"
    mv "$tmp" "$box/$ID-install-$1.json" && echo "$VER $1" >> "$REPORTED"
    return 0
}

# ---------------------------------------------------------------- status (read by the JMK MAP menu's root daemon)
# ver= state=locked|reboot|active|failed set= patched=<tags> reason= knobs=<config keys with a switch> warn=
patched_list() {
    local t id f out=
    for t in $TARGETS; do
        split_target "$t"
        [ "$(md5of "$(live_of "$(t_main)")")" = "$T_WANT" ] && out="$out,$(tag_of "$T_NAME")"
    done
    for f in libev6aac.so $(for id in $RECIPE_IDS; do recipe_file "$id"; done); do
        [ -f "$LIB_DIR/$f" ] || continue
        has_line "$f $(md5of "$LIB_DIR/$f")" "$APPLIED" || has_line "$f $(md5of "$LIB_DIR/$f")" "$ADDED" || continue
        out="$out,$(tag_of "$f")"
    done
    echo "${out#,}"
}
knob_keys() {
    local l
    [ -n "$SET" ] && [ -f "$(set_dir "$SET")/knobs" ] || return 0
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in ''|'#'*) continue ;; esac
        echo $l
    done < "$(set_dir "$SET")/knobs"
}
knobs_list() { local k out=; for k in $(knob_keys); do out="$out,$k"; done; echo "${out#,}"; }

write_status() {   # write_status <state> <reason>
    local tmp=$STATUS.tmp
    mkdir -p "$STORE" 2>/dev/null
    {
        echo "ver=$VER"; echo "state=$1"; echo "set=$SET"; echo "patched=$(patched_list)"; echo "reason=$2"
        echo "knobs=$(knobs_list)"; echo "warn=$WARN"
    } > "$tmp" 2>/dev/null || return 1
    chmod 0644 "$tmp"
    mv "$tmp" "$STATUS"
}
status_get() {
    local l
    [ -f "$STATUS" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$1="*) echo "${l#*=}"; return 0 ;; esac; done < "$STATUS"
    return 1
}

boot_token() {
    local b
    b=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
    [ -n "$b" ] || b=$(getprop ro.runtime.firstboot)
    echo "$b"
}

# boot_check (the service, once per start): state=reboot becomes active on a later boot that finds every file we
# wrote (the applied record: the rebuilt apps, the receiver library, the recipe libraries) in place, or failed.
boot_check() {
    local b f s miss= n=0
    [ "$(status_get state)" = reboot ] || return 0
    b=$(boot_token)
    [ -n "$b" ] && [ "$b" = "$(cat "$BOOT_FILE" 2>/dev/null)" ] && return 0
    WARN=$(status_get warn)
    [ -f "$APPLIED" ] || { write_status failed "after the reboot: no record of the patched files"; return 0; }
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        [ "$(md5of "$(live_of "$f")")" = "$s" ] || miss="$miss $f"
    done < "$APPLIED"
    if [ -z "$miss" ] && [ $n -gt 0 ]; then
        write_status active ""
        log "boot: every patched file ($n) is in place after the reboot: active"
    else
        write_status failed "after the reboot these are not the patched files:${miss:- none recorded}"
        log "boot: FAIL: not the patched files after the reboot:$miss"
        report boot-failed "$miss"
    fi
    return 0
}

# ---------------------------------------------------------------- the settings bridge (menu config -> switches)
# The patched apps read HMG Leafia Plus's persist.leafia.* switches. Our menu's config keys
# (tools/jmk-autoplay/DESIGN-hud.md §4) that have one; the set's knobs file says which ones its builds read.
knob_props() {
    case "$1" in
        log) echo "persist.leafia.log persist.leafia.lane.log" ;;   # Leafia writes both for its "log" key
        lane_dist) echo persist.leafia.lane.dist ;;
        cp_lanes) echo persist.leafia.cp.lanes ;;                   # the bridge Iap2ServerApp: ask CarPlay for lanes
        *) return 1 ;;
    esac
}
# knob_value <key> <config value>: the switch value; anything but a valid value gives the default (Leafia r8's)
knob_value() {
    case "$1" in
        log) case "$2" in 0) echo 0 ;; *) echo 1 ;; esac ;;
        lane_dist) case "$2" in 0) echo off ;; *) echo label ;; esac ;;
        cp_lanes) case "$2" in 0) echo 0 ;; *) echo 1 ;; esac ;;
        *) return 1 ;;
    esac
}
# Switches of Leafia builds we do not ship (bridge, BtSettings) and the ones its r8 runtime retired: never ours. A value
# left by an earlier Leafia install is cleared so the patched apps run with their defaults.
LEAFIA_OTHER_PROPS="persist.leafia.lane.src persist.leafia.lane.hl persist.leafia.lane.mode persist.leafia.lane.gauge persist.leafia.lane.dim persist.leafia.lane.gate persist.leafia.turn.split persist.leafia.tbt.standard persist.leafia.owner.r4bridge persist.leafia.delete.aa"
LEAFIA_PROPS="persist.leafia.log persist.leafia.lane.log persist.leafia.lane.dist persist.leafia.cp.lanes $LEAFIA_OTHER_PROPS"

conf_get() {
    local l
    [ -f "$CONF" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$1="*) echo "${l#*=}"; return 0 ;; esac; done < "$CONF"
    return 1
}

# apply_config [force]: when the config changed (or force), each knob's switch set to its value (only when it differs)
CONF_SIG=
apply_config() {
    local sig= l k want p changed=
    if [ -f "$CONF" ]; then
        while IFS= read -r l || [ -n "$l" ]; do sig="$sig|$l"; done < "$CONF"
    else
        sig=none
    fi
    [ "$1" = force ] || [ "$sig" != "$CONF_SIG" ] || return 0
    CONF_SIG=$sig
    for k in $(knob_keys); do
        want=$(knob_value "$k" "$(conf_get "$k")") || continue
        for p in $(knob_props "$k"); do
            [ "$(getprop "$p")" = "$want" ] && continue
            setprop "$p" "$want" && changed="$changed $p=$want"
        done
    done
    for p in $LEAFIA_OTHER_PROPS; do
        [ -n "$(getprop "$p")" ] || continue
        setprop "$p" "" && changed="$changed $p=(cleared)"
    done
    [ -n "$changed" ] && log "settings:$changed"
    return 0
}

# A real uninstall leaves no switch behind.
leafia_props_clear() {
    local p
    for p in $LEAFIA_PROPS; do [ -n "$(getprop "$p")" ] && setprop "$p" ""; done
    return 0
}

svc_stop() {
    local pid
    [ -f "$STORE/svc.pid" ] || return 0
    read -r pid < "$STORE/svc.pid" || pid=
    case "$pid" in
        ''|*[!0-9]*) ;;
        *) [ "$pid" != "$$" ] && grep -q 'svc/hud.sh' "/proc/$pid/cmdline" 2>/dev/null && kill "$pid" 2>/dev/null ;;
    esac
    rm -f "$STORE/svc.pid"
}
