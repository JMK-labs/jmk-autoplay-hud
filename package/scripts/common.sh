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
# 0.1.25 (GFQ4GE5F 2026-11-22: an install cut off left a file no record named, and the next run dropped the only stock
# copy with its record): three things outside $STORE, which no run deletes (the uninstall neither):
JOURNAL=$R/data/nemesis/$ID.journal  # every run and every /system write it meant and made, appended (capped, newest kept)
MADE=$R/data/nemesis/$ID.made        # "<file> <md5>" of every file any version of this package ever wrote: ours for good
ARCHIVE=$R/data/nemesis/backups/$ID.stock   # every stock copy ever kept, as <file>.<md5>, with index "<file> <md5> <fp>"
JOURNAL_KEEP=800
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

# unrecord <list> <file>: that file's line out of a "<file> <md5>" list
unrecord() {
    local l tmp=$1.tmp
    [ -f "$1" ] || return 0
    : > "$tmp" || return 1
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$2 "*) ;; *) echo "$l" >> "$tmp" ;; esac; done < "$1"
    mv "$tmp" "$1"
}
# forget <file>: no record of it any more (it is not ours to put back). 0.1.23 (GFQ4GE5F: a misjudged file took its only
# stock copy with it): the stock copy is never deleted, only moved to $BACKUP/dropped
forget() {
    local s
    s=$(lookup "$STOCK_LIST" "$1") && [ "$(md5of "$BACKUP/$1")" = "$s" ] && archive_put "$1" "$s" "$BACKUP/$1"
    unrecord "$STOCK_LIST" "$1"; unrecord "$APPLIED" "$1"
    [ -f "$BACKUP/$1" ] && mkdir -p "$BACKUP/dropped" 2>/dev/null && mv -f "$BACKUP/$1" "$BACKUP/dropped/$1" 2>/dev/null
    rm -f "$BACKUP/$1" 2>/dev/null
    true
}

# ---------------------------------------------------------------- 0.1.25: the journal, the made list, the archive
# j <words>: one journal line "<date> <pid> <words>"
j() { mkdir -p "${JOURNAL%/*}" 2>/dev/null; echo "$(date +%Y%m%d-%H%M%S) $$ $*" >> "$JOURNAL" 2>/dev/null; true; }
# j_begin <hook>: a run starts (the journal cut to its newest half past JOURNAL_KEEP lines); its end is written by the
# EXIT trap, so a run whose "end" is missing was cut off (power, a kill), not one that failed on its own
j_begin() {
    local n=0 k l
    if [ -f "$JOURNAL" ]; then
        while IFS= read -r l || [ -n "$l" ]; do n=$((n + 1)); done < "$JOURNAL"
        if [ $n -gt $JOURNAL_KEEP ]; then
            k=$((n - JOURNAL_KEEP / 2)); n=0
            : > "$JOURNAL.tmp"
            while IFS= read -r l || [ -n "$l" ]; do n=$((n + 1)); [ $n -gt $k ] && echo "$l" >> "$JOURNAL.tmp"; done < "$JOURNAL"
            mv "$JOURNAL.tmp" "$JOURNAL"
        fi
    fi
    J_HOOK=$1
    j_cutoff
    j "begin $1 $VER"
    trap 'j "end $J_HOOK rc=$?"' EXIT
}
# j_cutoff: the last run before this one that began and never ended: J_CUT="<hook> <ver>" and J_CUT_FILES (its
# intents with no "wrote" after them), reported once; empty when every run ended
j_cutoff() {
    local d p w h v f a b open= hook= ver= files=
    J_CUT=; J_CUT_FILES=
    [ -f "$JOURNAL" ] || return 0
    while read -r d p w h v f a || [ -n "$d" ]; do
        case "$w" in
            begin) open=$p; hook=$h; ver=$v; files= ;;
            end) [ "$p" = "$open" ] && open= ;;
            intent) [ "$p" = "$open" ] && files="$files $h" ;;
            wrote) [ "$p" = "$open" ] && { a=" $files "; files=; for b in $a; do [ "$b" = "$h" ] || files="$files $b"; done; } ;;
        esac
    done < "$JOURNAL"
    [ -n "$open" ] || return 0
    J_CUT="$hook $ver"; J_CUT_FILES=${files# }
    log "journal: the last run ($hook $ver, pid $open) was cut off${J_CUT_FILES:+, these writes not confirmed: $J_CUT_FILES}"
    j "cutoff $hook $ver ${J_CUT_FILES:-none}"
    report run-cut-off "$hook $ver; unconfirmed: ${J_CUT_FILES:-none}; product $(getprop ro.build.product)"
}
# j_intent <file> <md5 now> <md5 it will have>: before a write into /system (a put-back too); j_wrote <file> <md5>: after
j_intent() { j "intent $1 ${2:-none} ${3:-none}"; }
# j_ours <file> <md5 now> <md5 of our result>: before writing one of our results: the intent, and the result into the
# made list first (a cut-off write of it is then ours too). Never for a put-back: a stock md5 in the made list would
# make the stock file "ours"
j_ours() { made_add "$1" "$3"; j_intent "$1" "$2" "$3"; }
j_wrote() { j "wrote $1 ${2:-none}"; true; }
# made_add <file> <md5>: a result this package writes (before the write: a cut-off write of it is ours too)
made_add() {
    [ -n "$2" ] && [ "$2" != none ] || return 0
    has_line "$1 $2" "$STOCK_LIST" && return 0   # a stock md5 is never ours
    has_line "$1 $2" "$MADE" || { mkdir -p "${MADE%/*}" 2>/dev/null; echo "$1 $2" >> "$MADE"; }
    true
}
made() { [ -n "$2" ] && has_line "$1 $2" "$MADE"; }
# archive_put <file> <md5> <path>: a verified stock copy into the archive (once per md5), indexed with this firmware
archive_put() {
    local a=$ARCHIVE/$1.$2
    [ -n "$2" ] || return 1
    mkdir -p "$ARCHIVE" 2>/dev/null && chmod 0700 "$ARCHIVE" 2>/dev/null
    if [ "$(md5of "$a")" != "$2" ]; then
        rm -f "$a.tmp"
        cp "$3" "$a.tmp" 2>/dev/null && [ "$(md5of "$a.tmp")" = "$2" ] && mv "$a.tmp" "$a" || { rm -f "$a.tmp"; return 1; }
        chmod 0600 "$a"
    fi
    has_line "$1 $2 $(fp_now)" "$ARCHIVE/index" || echo "$1 $2 $(fp_now)" >> "$ARCHIVE/index"
    true
}
# archive_get <file> [<md5>]: the archived stock copy of that md5, or (none given) the one indexed for this firmware
archive_get() {
    local f s p want=$2
    [ -f "$ARCHIVE/index" ] || return 1
    if [ -z "$want" ]; then
        while read -r f s p || [ -n "$f" ]; do [ "$f" = "$1" ] && [ "$p" = "$(fp_now)" ] && want=$s; done < "$ARCHIVE/index"
    fi
    [ -n "$want" ] && [ "$(md5of "$ARCHIVE/$1.$want")" = "$want" ] && echo "$ARCHIVE/$1.$want"
}
# have_stock <file> <md5>: a verified stock copy in $BACKUP, brought back from the archive (same md5) when $BACKUP lost
# it; the one place every step asks (check_target, src_of), so they all see the same copies
have_stock() {
    local a
    [ -n "$2" ] || return 1
    [ "$(md5of "$BACKUP/$1")" = "$2" ] && return 0
    a=$(archive_get "$1" "$2") || return 1
    mkdir -p "$BACKUP" 2>/dev/null
    rm -f "$BACKUP/$1.tmp"
    cp "$a" "$BACKUP/$1.tmp" 2>/dev/null && [ "$(md5of "$BACKUP/$1.tmp")" = "$2" ] && mv "$BACKUP/$1.tmp" "$BACKUP/$1" || { rm -f "$BACKUP/$1.tmp"; return 1; }
    chmod 0600 "$BACKUP/$1"
    log "the stock copy of $1 ($2) brought back from the archive into $BACKUP"
    return 0
}
# archive_all: every verified stock copy of $BACKUP into the archive (cars that come from 0.1.24 or older)
archive_all() {
    local f s
    [ -f "$STOCK_LIST" ] || return 0
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] && [ -n "$s" ] || continue
        [ -f "$ARCHIVE/$f.$s" ] && continue
        [ "$(md5of "$BACKUP/$f")" = "$s" ] && archive_put "$f" "$s" "$BACKUP/$f"
    done < "$STOCK_LIST"
    true
}

# ---------------------------------------------------------------- 0.1.8: housekeeping (QA 2026-11-19 #15)
# size_kb <file>: its size in KB (toolbox ls -s prints "<KB> <name>"), 0 when absent
size_kb() { local n; set -- $(ls -s "$1" 2>/dev/null); n=$1; case "$n" in ''|*[!0-9]*) n=0 ;; esac; echo $n; }
# free_kb <dir>: KB free on its filesystem, empty when unknown. Toolbox df's last line is "<fs> <size> <used> <free>
# <blksize>" with sizes like 412.0M; busybox df has KB in the same (4th) column.
free_kb() {
    local out last v i f IFS
    out=$(df "$1" 2>/dev/null) || return 0
    IFS='
'
    set -f; set -- $out; set +f
    [ $# -ge 2 ] || return 0
    eval "last=\${$#}"
    IFS=' 	'
    set -f; set -- $last; set +f
    v=$4
    case "$v" in
        *K|*M|*G) ;;
        ''|*[!0-9]*) return 0 ;;
        *) echo "$v"; return 0 ;;
    esac
    i=${v%?}; f=0
    case "$i" in *.*) f=${i#*.}; i=${i%%.*}; f=${f%"${f#?}"} ;; esac
    case "$i$f" in ''|*[!0-9]*) return 0 ;; esac
    case "$v" in
        *K) echo $i ;;
        *M) echo $((i * 1024 + f * 1024 / 10)) ;;
        *G) echo $((i * 1048576 + f * 104857)) ;;
    esac
}
# log_cap: a log over 256 KB becomes <log>.old (one generation kept); lpatch's output goes into it on every install
log_cap() {
    local f
    for f in "$LOG" "$@"; do [ -f "$f" ] && [ "$(size_kb "$f")" -gt 256 ] && mv "$f" "$f.old" 2>/dev/null; done
    true
}
# clean_tmp: put_file's "<target>.jmkhud" copies left by a swap that was cut off (power, a killed hook)
clean_tmp() {
    local f
    for f in "$APP_DIR"/*.jmkhud "$LIB_DIR"/*.jmkhud; do
        [ -e "$f" ] || continue
        rm -f "$f" 2>/dev/null && log "removed a leftover copy $f"
    done
    true
}

# ---------------------------------------------------------------- 0.1.8: the firmware the records belong to (QA #1)
# FP_FILE holds ro.build.fingerprint from when the records were last made true to this firmware. A firmware update
# replaces the stock apps: their old stock copies must never go over the new firmware's files.
FP_FILE=$STORE/fingerprint
fp_now() { getprop ro.build.fingerprint; }
fw_changed() { [ -f "$FP_FILE" ] && [ "$(cat "$FP_FILE" 2>/dev/null)" != "$(fp_now)" ]; }
fw_same() { [ -f "$FP_FILE" ] && ! fw_changed; }
fp_save() { local t=$FP_FILE.tmp; fp_now > "$t" 2>/dev/null && mv "$t" "$FP_FILE"; }

# ours <file> <live md5> (the live md5 is not the recorded stock one; every caller checked that first): the live file
# is this package's, to replace or to put back. Written by this package (APPLIED); an .odex follows its apk (our dexopt
# writes it, so its md5 is never known before): the apk is ours, or (same firmware only) the apk is the recorded stock
# one already: a put-back that stopped between the apk and its odex (an uninstall, a rollback or the tamper lock's
# put-back cut off: a power cut, a write that failed). On another firmware a stock apk may have a new odex (a new
# framework), never ours.
# 0.1.38 (the firmware-change review 2026-11-26): an .odex is judged by its own md5 first: ours when that md5 is in the
# made list (apply_target records what our dexopt wrote). Its apk is looked at only on the firmware the records were
# made for: when the fingerprint differs from the recorded one, an odex that is not in the made list is the new
# firmware's, whatever its apk is (before, an apk of ours made the odex ours on any firmware, and an uninstall, the
# update's stale step or the tamper lock wrote the old firmware's stock odex over the new one). A missing odex has
# nothing to be written over: it is judged by its apk on any firmware.
# 0.1.15 (DPPB5BHV, Kia EV6 Korea, 2026-11-20): one rule for the gate, the by-code build, the put-back and the firmware
# check. Before, the gate's ours() knew only "the apk is in APPLIED" while the put-back's restorable() (this rule) also
# knew the half-way case: an odex the uninstall would have put back was "not ours" to the next install, which then
# took that patched odex for the stock one (plan_src) and kept the earlier version's build on every later version.
# 0.1.17 (GMI6OZC2, Ioniq 5 Korea, 2026-11-20): or a result an earlier version wrote (patches/known, src/mkknown.py: the
# rebuilt .apk of every fixed set and every rebuilt library of any version). That car's HKMC_GPM.apk is 1c4bfdda, the
# neev_kr GPM build of 0.1.0-0.1.4 (Leafia KR r8.2's, byte for byte), with no applied line for it: every version since
# locked it as another tool's file. Ours, it is rebuilt from its verified stock copy (check_target, stock_copy); without
# one it stays as it is, and the reason says so.
KNOWN=$PATCHES/known
known() { [ -n "$2" ] && has_line "$1 $2" "$KNOWN"; }
ours() {
    local f=$1 apk a
    case "$f" in
        *.odex)
            [ -n "$2" ] && made "$f" "$2" && return 0   # 0.1.38: its own md5, the one our dexopt wrote
            [ -f "$(live_of "$f")" ] && fw_changed && return 1   # 0.1.38: another firmware: only its own md5 counts
            apk=${f%.odex}.apk
            a=$(md5of "$(live_of "$apk")")
            [ -n "$a" ] || return 1
            has_line "$apk $a" "$APPLIED" && return 0
            made "$apk" "$a" && return 0   # 0.1.25: any version's own write (a cut-off install's too)
            known "$apk" "$a" && return 0
            ours_dex "$apk" && return 0   # 0.1.23: its apk holds a by-code result dex
            fw_same && [ "$a" = "$(lookup "$STOCK_LIST" "$apk")" ] ;;
        *) [ -n "$2" ] || return 1
           has_line "$f $2" "$APPLIED" || made "$f" "$2" || known "$f" "$2" || ours_dex "$f" ;;
    esac
}
# 0.1.23 (GFQ4GE5F, Casper Korea, 2026-11-22: after a reboot its HKMC_DiPO.apk was 1e73e68b, not the md5 the install
# recorded, though its classes.dex was 0.1.22's own result d89ed80a; every later install locked it as another tool's
# file): an .apk whose classes.dex is a by-code result of any version (patches/known "<name>.dex <md5>", src/mkknown.py)
# is ours. Asked only when the apk md5 is neither recorded nor known (tools/codesum.jar apkdex, an app_process run).
ours_dex() {
    local f=$1 base d
    case "$f" in *.apk) ;; *) return 1 ;; esac
    base=${f%.apk}
    grep -q "^$base\.dex " "$KNOWN" 2>/dev/null || return 1
    d=$(codesum apkdex "$(live_of "$f")")
    d=${d#dex=}
    [ -n "$d" ] && [ "$d" != none ] && known "$base.dex" "$d"
}
restorable() { ours "$1" "$2"; }   # the put-back's name for it (restore_files, fw_reconcile)

# fw_reconcile: after a firmware update, the records of every file the new firmware replaced (neither the recorded
# stock file nor ours) go with their stock copies; the fingerprint is then this firmware's. 1 when nothing changed.
fw_reconcile() {
    local f s got drop= old
    fw_changed || return 1
    old=$(cat "$FP_FILE" 2>/dev/null)
    log "firmware changed: $old -> $(fp_now)"
    if [ -f "$STOCK_LIST" ]; then
        while read -r f s || [ -n "$f" ]; do
            [ -n "$f" ] && [ -n "$s" ] || continue
            got=$(md5of "$(live_of "$f")")
            [ "$got" = "$s" ] && continue
            restorable "$f" "$got" && continue
            drop="$drop $f"
        done < "$STOCK_LIST"
        for f in $drop; do
            log "firmware changed: $(live_of "$f") is the new firmware's: the old stock copy and its record dropped"
            report firmware-changed "left as it is: ${f} md5 $(md5of "$(live_of "$f")"), saved stock $(lookup "$STOCK_LIST" "$f"); firmware $old -> $(fp_now)"
            forget "$f"
        done
    fi
    if [ -f "$ADDED" ]; then
        while read -r f s || [ -n "$f" ]; do
            [ -n "$f" ] || continue
            [ "$(md5of "$(live_of "$f")")" = "$s" ] || { log "firmware changed: $(live_of "$f") is not the one we added: record dropped"; unrecord "$ADDED" "$f"; }
        done < "$ADDED"
    fi
    fp_save
    return 0
}

# ---------------------------------------------------------------- patch sets (Leafia's patches/ layout)
#   patches/cars              <ro.build.product prefix> <set> <car name>
#   patches/<set>/stock       <file> <md5 of the stock file>
#   patches/<set>/manifest    2_tbt <app|file> <name> <patch> <md5 of the rebuilt file>
#   patches/<set>/knobs       the menu config keys this set's builds read (ours; absent = none)
# 0.1.4: "auto" is the set the by-code build made for this car (in our state, so it outlives package updates)
set_dir() { if [ "$1" = auto ]; then echo "$AUTO"; else echo "$PATCHES/$1"; fi; }
# 0.1.27: an auto set whose every file was kept (no stock copy at all, VEBJD2LL after a full reinstall) has an empty
# stock list but a kept list
set_ok() { local d; [ -n "$1" ] || return 1; d=$(set_dir "$1"); [ -s "$d/manifest" ] && { [ -s "$d/stock" ] || [ -s "$d/kept" ]; }; }
stock_sum() { lookup "$(set_dir "$SET")/stock" "$1"; }
# 0.1.17: a fixed set with a "superseded" file (patches/dl3hev: Leafia's original build, none of our changes) is the
# fallback: postinstall tries the by-code profiles first and takes the set only when none fits
set_superseded() { [ -n "$1" ] && [ "$1" != auto ] && [ -f "$(set_dir "$1")/superseded" ]; }

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
# 0.1.24 (PDILCGAW, TS5NC2G5, WFAJ6EKE: Kia EV6 Korea kept 0.1.18 / 0.1.20's builds, "HKMC_GPM's code is , not
# 9759e803" within a second; GFQ4GE5F once too): every run has its own output file (one shared codesum.out could be
# removed or overwritten by another run of the add-on, the service or an install, at the same moment), and an empty
# answer that came at once (not a hang: that stays one 20 s wait) is asked once more.
codesum() {
    local out t0 t1
    t0=$(date +%s 2>/dev/null)
    out=$(codesum_once "$@")
    if [ -z "$out" ]; then
        t1=$(date +%s 2>/dev/null)
        if [ -n "$t0" ] && [ -n "$t1" ] && [ $((t1 - t0)) -lt 15 ]; then
            echo "$(date) codesum $1: no answer after $((t1 - t0)) s, once more" >> "$LOG"
            out=$(codesum_once "$@")
        fi
    fi
    echo "$out"
}
codesum_once() {
    local jar pid n out= f
    jar=$(cd "$PKG" 2>/dev/null && pwd)/tools/codesum.jar
    [ -f "$jar" ] || return 0
    mkdir -p "$STORE" 2>/dev/null
    f=$STORE/codesum.$$.$(date +%s 2>/dev/null).$RANDOM.out
    rm -f "$f"
    CLASSPATH=$jar app_process /system/bin jmkhud.CodeSum "$@" > "$f" 2>/dev/null &
    pid=$!
    n=0
    while kill -0 "$pid" 2>/dev/null && [ $n -lt 20 ]; do sleep 1; n=$((n + 1)); done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ -f "$f" ] && read -r out < "$f"
    rm -f "$f"
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

# stock_copy <file>: prints the stock file to build from (0.1.15, DPPB5BHV, Kia EV6 Korea, 2026-11-20). Status 1 and
# nothing printed when there is none (the log says why).
#  - recorded in STOCK_LIST (an earlier version of this package patched it; fw_reconcile has made the records true to
#    this firmware): our copy in $BACKUP when its md5 is the recorded stock md5, else the live file when that is the
#    recorded stock one; else none: a missing or damaged copy next to a live file that is not stock is never a source;
#  - never recorded (a file this package never wrote): the live file, unless it is ours (then none).
# Before, plan_src() gave "our backup when the live file is ours, else the live file", with ours() (the apk's md5 in
# APPLIED) as the only judge and no md5 check of the copy. When that judge said no for a file an earlier version had
# patched (DPPB5BHV's 0.1.10 update over 0.1.9: postinstall-kept-old "nor its code a profile"), the LIVE, patched
# odex was read as the stock one: its code is the patched code, which fits no profile, so the update kept the earlier
# build, and so would every later version. Where the stock file is no longer depends on whose the live file is: that
# decides only whether the live file may be replaced (check_target, with ours() above).
stock_copy() {
    local f=$1 s live got
    live=$(live_of "$f")
    if s=$(lookup "$STOCK_LIST" "$f"); then
        [ "$(md5of "$BACKUP/$f")" = "$s" ] && { echo "$BACKUP/$f"; return 0; }
        got=$(md5of "$live")
        [ "$got" = "$s" ] && { echo "$live"; return 0; }
        got=$(archive_get "$f" "$s") && { echo "$got"; return 0; }   # 0.1.25
        echo "$(date) by code: no stock copy of $f: the copy in $BACKUP is not the recorded stock $s (md5 $(md5of "$BACKUP/$f")), the live one is ${got:-missing}" >> "$LOG"
        return 1
    fi
    got=$(md5of "$live")
    # 0.1.23: a missing file is no stock copy (GFQ4GE5F: HKMC_DiPO.odex gone; before, its path was given and read as
    # code "none")
    [ -f "$live" ] || { echo "$(date) by code: no $live and no stock record of it" >> "$LOG"; return 1; }
    if ours "$f" "$got"; then
        # 0.1.25: its stock copy from the archive (indexed for this firmware), when one is there
        s=$(archive_get "$f") && { echo "$(date) by code: $live is ours, its stock copy from the archive" >> "$LOG"; echo "$s"; return 0; }
        echo "$(date) by code: $live is ours but has no stock record: not a stock file" >> "$LOG"
        return 1
    fi
    echo "$live"
}

# 0.1.23 (GFQ4GE5F, Casper Korea, 2026-11-22): an app with no stock copy at all (its records and copies dropped by an
# earlier version that took our own build for another tool's) whose live .apk holds a by-code result dex: KEPT gets
# " <App>=<dex md5>" and KEPT_CODES " <App>.code=<stock code>" from the profile line that builds exactly that dex, so
# the profile can fit; bycode_make then keeps the live apk as that line's build (no stock copy: an uninstall leaves it,
# the reason says so) instead of locking the car for good.
kept_scan() {
    local n=$1 a d dir p k m c x w found= codes=
    a=$(live_of "$n.apk")
    [ -f "$a" ] && ours_dex "$n.apk" || return 1
    d=$(codesum apkdex "$a"); d=${d#dex=}
    # 0.1.26 (VEBJD2LL: DiPO's bridge build d89ed80a is the same result on kra and krb; only kra's code was kept, so
    # krb never fitted): every profile line that builds exactly this dex gives its code
    for dir in "$BYCODE"/*/manifest; do
        [ -f "$dir" ] || continue
        while read -r p k m c x w || [ -n "$p" ]; do
            [ "$k" = app ] && [ "$m" = "$n" ] && [ "$w" = "$d" ] || continue
            found=1
            case " $KEPT_CODES " in *" $n.code=$c "*) ;; *) KEPT_CODES="$KEPT_CODES $n.code=$c"; codes="$codes $c" ;; esac
        done < "$dir"
    done
    [ -n "$found" ] || return 1
    KEPT="$KEPT $n=$d"
    echo "$(date) by code: $n has no stock copy; its live apk holds the by-code result $d (code$codes): kept as that build" >> "$LOG"
    return 0
}

# 0.1.26 (VEBJD2LL, CN7HEV 2026-11-23: after a full remove and reinstall the apps were kept by kept_scan, but the
# turn-by-turn library had no stock copy and locked the car): the same for a library. Its live file is exactly a
# profile line's result (w): KEPT gets " <lib>=<w>" and KL_C the stock md5 that line names (c), so the part can fit
kept_lib() {
    local n=$1 live got dir p k m c x w
    live=$(live_of "$n")
    [ -f "$live" ] || return 1
    got=$(md5of "$live")
    [ -n "$got" ] || return 1
    KL_C=
    for dir in "$BYCODE"/*/manifest; do
        [ -f "$dir" ] || continue
        while read -r p k m c x w || [ -n "$p" ]; do
            [ "$k" = file ] && [ "$m" = "$n" ] && [ "$w" = "$got" ] || continue
            case " $KL_C " in *" $c "*) ;; *) KL_C="${KL_C:+$KL_C }$c" ;; esac   # every profile's stock md5 for it
        done < "$dir"
    done
    [ -n "$KL_C" ] || return 1
    KEPT="$KEPT $n=$got"   # globals: never call this inside $( ) (a subshell would drop them)
    echo "$(date) by code: $n has no stock copy; the live one is the by-code result $got (stock $KL_C): kept as that build" >> "$LOG"
    return 0
}

# the apps any profile names, once (bycode_names app); the libraries (bycode_names file)
bycode_names() {
    local d p k n c x w out=" "
    for d in "$BYCODE"/*/manifest; do
        [ -f "$d" ] || continue
        while read -r p k n c x w || [ -n "$p" ]; do
            case "$p" in ''|'#'*) continue ;; esac
            [ "$k" = "$1" ] || continue
            case "$out" in *" $n "*) ;; *) out="$out$n " ;; esac
        done < "$d"
    done
    echo $out
}
bycode_apps() { bycode_names app; }

# bycode_part_fits <profile dir> <part> <" App.code=<md5> ..."> <" lib=<md5> ...">: every line of the part matches
# this car's stock code (the odex lines) and stock libraries (the file lines), both from stock_copy
bycode_part_fits() {
    local p k n c x w any=
    while read -r p k n c x w || [ -n "$p" ]; do
        case "$p" in ''|'#'*) continue ;; esac
        [ "$p" = "$2" ] || continue
        any=1
        if [ "$k" = app ]; then
            case "$3" in *" $n.code=$c "*) ;; *) return 1 ;; esac
        else
            case "$4" in *" $n=$c "*) ;; *) return 1 ;; esac
        fi
    done < "$1/manifest"
    [ -n "$any" ] || return 1
    # 0.1.20: "bridge_products <ro.build.product> ...": the bridge only on the firmwares whose framework was seen (its
    # android:id numbers are what the bridge's PhoneProjection uses); other cars of the same app code keep turn-by-turn
    if [ "$2" = 3_bridge ]; then
        local a b bp=
        while read -r a b || [ -n "$a" ]; do [ "$a" = bridge_products ] && bp="$bp $b"; done < "$1/manifest"
        if [ -n "$bp" ]; then case " $bp " in *" $(getprop ro.build.product) "*) ;; *) bridge_fw_seen "$1" || return 1 ;; esac; fi
    fi
    return 0
}

# 0.1.28 (the owner, 2026-11-23: every car of a seen framework, not only its products): "bridge_framework <file>=<md5>
# ..." in a profile's manifest (files under /system/framework): a car whose files are all these runs the framework
# that was seen (the bridge's android:id numbers and outside refs), whatever its product. Logged either way.
# 0.1.32: one line is one seen framework; several lines are alternatives (a car of any one of them gets the bridge).
# framework-res.apk differs between cars whose resources.arsc (the android:id numbers) is the same, so a car with
# another apk of that arsc is one more line.
bridge_fw_seen() {
    local a rest f m got all= bad= line first=1
    while read -r a rest || [ -n "$a" ]; do
        [ "$a" = bridge_framework ] || continue
        line= ; bad=
        for f in $rest; do
            m=${f#*=}; f=${f%%=*}
            got=$(md5of "$R/system/framework/$f")
            [ "$got" = "$m" ] || bad="$bad $f=${got:-none}"
            line="$line $f=$m"
        done
        if [ -z "$bad" ]; then log "bridge (${1##*/}): $(getprop ro.build.product) runs the framework seen (${line# }): bridge on"; return 0; fi
        all="$all${all:+;}$bad"
    done < "$1/manifest"
    [ -n "$all" ] || return 1
    log "bridge (${1##*/}): this framework is not the one seen:$all"
    return 1
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
        if [ "$k" = app ] && case " $KEPT " in *" $n=$w "*) true ;; *) false ;; esac; then
            # 0.1.23: no stock copy, the live apk is exactly this line's build (kept_scan): kept, no stock lines
            cp "$(live_of "$n.apk")" "$new/built/$p.$n.apk" 2>/dev/null || { BYCODE_WHY="${dir##*/}: could not copy the kept $n"; rm -rf "$new"; return 1; }
            echo "$p app $n prebuilt:$p.$n.apk $(md5of "$new/built/$p.$n.apk")" >> "$new/manifest"
            echo "$n" >> "$new/kept"
            continue
        fi
        if [ "$k" = app ]; then
            # 0.1.15: only verified stock copies (stock_copy); the md5s written to the set's stock list are theirs
            src=$(stock_copy "$n.odex") && apk=$(stock_copy "$n.apk") && [ -f "$apk" ] || {
                BYCODE_WHY="${dir##*/}: no stock copy of $n"; echo "$(date) by code: no stock $n.apk / $n.odex" >> "$LOG"; rm -rf "$new"; return 1; }
            got=$(codesum extract "$src" "$new/code.dex")
            [ "$got" = "code=$c" ] || {
                BYCODE_WHY="${dir##*/}: $n's code is ${got#code=}"; echo "$(date) by code: $n's code is ${got#code=}, not $c" >> "$LOG"; rm -rf "$new"; return 1; }
            rm -f "$new/classes.dex"
            "$LPATCH" delta "$PATCHES/$x" "$new/code.dex" "$new/classes.dex" >> "$LOG" 2>&1 &&
                [ "$(md5of "$new/classes.dex")" = "$w" ] &&
                "$LPATCH" zipadd "$apk" "$new/classes.dex" "$new/built/$p.$n.apk" >> "$LOG" 2>&1 || {
                BYCODE_WHY="${dir##*/}: $n ($p) did not rebuild"
                echo "$(date) by code: $n ($p) did not rebuild to the profile's code $w" >> "$LOG"; rm -rf "$new"; return 1; }
            rm -f "$new/code.dex" "$new/classes.dex"
            echo "$p app $n prebuilt:$p.$n.apk $(md5of "$new/built/$p.$n.apk")" >> "$new/manifest"
            case "$seen" in *" $n "*) ;; *)
                seen="$seen$n "
                echo "$n.apk $(md5of "$apk")" >> "$new/stock"
                echo "$n.odex $(md5of "$src")" >> "$new/stock" ;;
            esac
        elif case " $KEPT " in *" $n=$w "*) true ;; *) false ;; esac && ! stock_copy "$n" >/dev/null; then
            # 0.1.26: a library with no stock copy, live exactly this line's result (kept_lib): kept, no stock line
            cp "$(live_of "$n")" "$new/built/$p.$n" 2>/dev/null || { BYCODE_WHY="${dir##*/}: could not copy the kept $n"; rm -rf "$new"; return 1; }
            echo "$p file $n prebuilt:$p.$n $(md5of "$new/built/$p.$n")" >> "$new/manifest"
            echo "$n" >> "$new/kept"
        else
            src=$(stock_copy "$n") && [ "$(md5of "$src")" = "$c" ] || {
                BYCODE_WHY="${dir##*/}: no stock copy of $n"; echo "$(date) by code: no stock $n" >> "$LOG"; rm -rf "$new"; return 1; }
            "$LPATCH" delta "$PATCHES/$x" "$src" "$new/built/$p.$n" >> "$LOG" 2>&1 && [ "$(md5of "$new/built/$p.$n")" = "$w" ] || {
                BYCODE_WHY="${dir##*/}: $n ($p) did not rebuild"
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

# bycode_build: 0 and $AUTO made when a profile has a part this car's code fits (quiet: the caller logs).
# 0.1.15: the code and the libraries come from stock_copy (on an update: our verified copies in $BACKUP, never the
# patched live files). BYCODE_CODES: the stock code it chose by (the other-model-set report; before, that report read
# the live odex, so an update over our own files reported the patched code: DPPB5BHV's 0.1.9 9c66644c / 7df6b900 ...,
# the same on every car that updated, which is not what the profile was chosen from). BYCODE_WHY: why nothing was made
# (the locked / kept-old report; before, it said only "nor its code a profile").
bycode_build() {
    local n s args= codes libs=" " miss= bak= dir parts part
    BYCODE_CODES=; BYCODE_WHY=; KEPT=; KEPT_CODES=
    [ -d "$BYCODE" ] || { BYCODE_WHY="no profiles"; return 1; }
    for n in $(bycode_apps); do
        if s=$(stock_copy "$n.odex"); then args="$args $s"; else kept_scan "$n" || miss="$miss $n.odex"; continue; fi
        case "$s" in "$BACKUP"/*) bak=1 ;; esac
    done
    for n in $(bycode_names file); do
        if s=$(stock_copy "$n"); then
            case "$s" in "$BACKUP"/*) bak=1 ;; esac
            s=$(md5of "$s"); [ -n "$s" ] || { s=none; miss="$miss $n"; }
        else
            if kept_lib "$n"; then   # 0.1.26: each profile's stock md5 for it, so any of them can fit
                for s in $KL_C; do libs="$libs$n=$s "; done
                continue
            else s=none; miss="$miss $n"; fi
        fi
        libs="$libs$n=$s "
    done
    # 0.1.26: every app kept (no stock copy of any, VEBJD2LL after a full reinstall): the kept codes alone choose
    [ -n "$args" ] || [ -n "$KEPT_CODES" ] || { BYCODE_WHY="no stock copy of:$miss"; return 1; }
    if [ -n "$args" ]; then codes=" $(codesum $args)$KEPT_CODES "; else codes=" $KEPT_CODES "; fi
    echo "$(date) by code: this car's stock code:$codes(${miss:+no stock copy of$miss; }libraries$libs)" >> "$LOG"
    case "$codes" in
        *.code=*) BYCODE_CODES=$(echo $codes) ;;
        *) BYCODE_WHY="the code helper (tools/codesum.jar) gave no answer${miss:+; no stock copy of$miss}"; return 1 ;;
    esac
    # the profile that fits the most parts wins (0.1.6): kra fits K8's turn-by-turn and bridge, kr its turn-by-turn only,
    # so the first profile that fits anything (kr, by name) would leave K8 without the bridge; equal counts keep the
    # name order. Both parts first, then one part.
    local want
    for want in 2 1; do
        for dir in "$BYCODE"/*; do
            [ -s "$dir/manifest" ] || continue
            parts=
            for part in 2_tbt 3_bridge; do bycode_part_fits "$dir" "$part" "$codes" "$libs" && parts="$parts $part"; done
            set -- $parts
            [ $# -eq $want ] || continue
            bycode_make "$dir" "$parts" && { BYCODE_WHY=; return 0; }
        done
    done
    # 0.1.8 (QA #7): an earlier by-code build stays: it describes the files an earlier version patched, still live
    # no profile fits: which stock copy was missing, and the code and libraries of our stock copies when they were read
    # (those of the live files are in the locked report already)
    [ -n "$BYCODE_WHY" ] || BYCODE_WHY="${miss:+no stock copy of$miss}${bak:+${miss:+; }code of the stock copies $BYCODE_CODES, libraries$libs}"
    BYCODE_WHY=$(echo $BYCODE_WHY)
    return 1
}

# set_fits <set>: every target of the set is this car's stock file, or ours with the stock copy in $BACKUP
set_fits() {
    local SET=$1 TARGETS t T_HOW REASON
    load_targets || return 1
    for t in $TARGETS; do split_target "$t"; check_target || return 1; done
    return 0
}

# 0.1.17: what the stock snapshots of Leafia / projection.tbt (/data/nemesis/backup/<part>, flat names) still hold of
# this set's stock files, as "<part>:<file>,..." words; empty when there is no snapshot. For the locked report only
# (GMI6OZC2: Leafia KR's builds live, no stock copy of ours): never a source.
leafia_copies() {
    local d f s got out=
    [ -n "$SET" ] && [ -f "$(set_dir "$SET")/stock" ] || return 0
    for d in "$R/data/nemesis/backup/projection.tbt" "$R/data/nemesis/backup/wireless.carplay.bt"; do
        [ -d "$d" ] || continue
        got=
        while read -r f s || [ -n "$f" ]; do
            case "$f" in ''|'#'*) continue ;; esac
            [ "$(md5of "$d/$f")" = "$s" ] && got="$got,$f"
        done < "$(set_dir "$SET")/stock"
        out="$out ${d##*/}:${got#,}"
    done
    echo "${out# }"
}

# ---------------------------------------------------------------- the stock md5 gate
# (ours <file> <live md5>: above, with restorable)

# check_target: T_HOW=done (this version's file is in place already) or build (the stock copies are at hand: live, or
# our backup when the live one is ours). Returns 1 with REASON when a file is neither stock nor ours.
check_target() {
    local f s got main
    main=$(t_main)
    # 0.1.23: an app the by-code build kept (no stock copy, already exactly this build): done, nothing to back up
    if [ "$SET" = auto ] && has_line "$T_NAME" "$AUTO/kept" && [ "$(md5of "$(live_of "$main")")" = "$T_WANT" ]; then   # 0.1.26: a library too
        T_HOW=done
        WARN="${WARN:+$WARN; }$T_NAME kept as this add-on's build (no stock copy: an uninstall leaves it)"
        return 0
    fi
    for f in $(t_files); do
        stock_sum "$f" >/dev/null || { REASON="patch set $SET has no stock md5 for $f"; return 1; }
    done
    if [ "$(md5of "$(live_of "$main")")" = "$T_WANT" ]; then
        for f in $(t_files); do
            s=$(stock_sum "$f")
            have_stock "$f" "$s" || { REASON="$f is patched already but its stock copy is not in $BACKUP (nor in the archive)"; return 1; }
        done
        T_HOW=done
        return 0
    fi
    for f in $(t_files); do
        s=$(stock_sum "$f")
        got=$(md5of "$(live_of "$f")")
        [ "$got" = "$s" ] && continue
        if ours "$f" "$got"; then
            have_stock "$f" "$s" && continue   # 0.1.25: $BACKUP, else the archive
            # 0.1.17: ours (an earlier build of this add-on, or Leafia's identical one) but no stock copy to build from
            REASON="$f is a build of this add-on (md5 ${got:-missing}) but its stock copy ($s) is not in $BACKUP (nor in the archive)"
            return 1
        fi
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
    # 0.1.31: have_stock logs to stdout when it brings the copy back from the archive; src_of runs inside $(...), so that
    # line became part of the path (lpatch: MISSING, "could not rebuild HKMC_GPM"; six Ioniq 5 cars 2026-11-23). To stderr.
    if have_stock "$1" "$s" >&2; then echo "$BACKUP/$1"; else live_of "$1"; fi
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
    archive_put "$1" "$s" "$bak" || log "WARNING: $1 not archived (the copy in $BACKUP stays)"
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
# 0.1.8: whatever this write left in place is recorded as ours (a copy cut short too), so a rollback puts it back
applied_mark() {   # applied_mark <file> <its stock md5>
    local got
    got=$(md5of "$(live_of "$1")")
    [ -n "$got" ] && [ "$got" != "$2" ] && record "$APPLIED" "$1" "$got"
    true
}
apply_target() {
    local live ok=0
    live=$(live_of "$(t_main)")
    j_ours "$(t_main)" "$(md5of "$live")" "$T_WANT"
    put_file "$WORK/$(t_main)" "$live" || ok=1
    applied_mark "$(t_main)" "$(stock_sum "$(t_main)")"
    j_wrote "$(t_main)" "$(md5of "$live")"
    [ $ok -eq 0 ] || { REASON="could not write $live"; return 1; }
    [ "$(md5of "$live")" = "$T_WANT" ] || { REASON="$live does not have the rebuilt md5 after the write"; return 1; }
    if [ "$T_KIND" = app ]; then
        rm -f "$APP_DIR/$T_NAME.odex" 2>/dev/null
        [ -f "$APP_DIR/$T_NAME.odex" ] && { REASON="could not delete $APP_DIR/$T_NAME.odex"; return 1; }
        if write_odex "$live" "$APP_DIR/$T_NAME.odex"; then
            made_add "$T_NAME.odex" "$(md5of "$APP_DIR/$T_NAME.odex")"
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

# restore_files [<files>]: every file in STOCK_LIST (or only those named) back to its stock copy (md5 checked);
# REASON names the first failure. 0.1.8 (QA 2026-11-19 #1): only a live file that is ours (restorable) is written. One
# that is neither stock nor ours (after a firmware update: the new firmware's own apk, odex or library) is left alone
# and its record dropped: the old firmware's odex over it broke those apps until a reflash. Who is whose is decided
# for every file before the first write (an odex follows its apk, which goes back first).
restore_files() {
    local f s live got src todo= drop= bad=0
    [ -f "$STOCK_LIST" ] || return 0
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] && [ -n "$s" ] || continue
        [ -z "$1" ] || case " $1 " in *" $f "*) ;; *) continue ;; esac
        live=$(live_of "$f")
        got=$(md5of "$live")
        [ "$got" = "$s" ] && continue
        if restorable "$f" "$got"; then
            todo="$todo $f"
        else
            log "left alone: $live is not ours (md5 ${got:-missing}, stock $s; a firmware update or another package wrote it): its record dropped"
            fw_changed && report firmware-changed "left as it is: ${live##*/} md5 ${got:-missing}, saved stock $s; firmware $(cat "$FP_FILE" 2>/dev/null) -> $(fp_now)"
            drop="$drop $f"
        fi
    done < "$STOCK_LIST"
    for f in $drop; do forget "$f"; done
    for f in $todo; do
        s=$(lookup "$STOCK_LIST" "$f")
        live=$(live_of "$f")
        src=$BACKUP/$f
        if [ "$(md5of "$src")" != "$s" ]; then
            # 0.1.25: the archive's copy of the same md5
            if src=$(archive_get "$f" "$s"); then log "the stock copy of $f in $BACKUP is missing or damaged: the archive's copy is used"
            else
                [ -n "$REASON" ] || REASON="the stock copy of $f is missing or damaged in $BACKUP (and not in the archive)"
                bad=1; continue
            fi
        fi
        j_intent "$f" "$(md5of "$live")" "$s"
        if put_file "$src" "$live" && [ "$(md5of "$live")" = "$s" ]; then
            j_wrote "$f" "$s"
            log "restored $f (stock $s)"
        else
            [ -n "$REASON" ] || REASON="could not put back $live"
            bad=1
        fi
    done
    return $bad
}

# 0.1.8 (QA #7): the files STOCK_LIST holds that no target of this version and no recipe names (an earlier version's
# or profile's), as words
untargeted() {
    local f s t id want=" " out=
    [ -f "$STOCK_LIST" ] || return 0
    for t in $TARGETS; do split_target "$t"; want="$want$(t_files) "; done
    for id in $RECIPE_IDS; do f=$(recipe_file "$id") && want="$want$f "; done
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        case "$want" in *" $f "*) ;; *) out="$out $f" ;; esac
    done < "$STOCK_LIST"
    echo $out
}

# 0.1.8 (QA #4): KB /system needs for the swap: each new file is copied beside its target before the rename (the old
# one is freed after it), so the growth of every file plus the biggest copy, plus 1 MB for the odex and the records.
# swap_need_kb <targets> <recipe ids> <files put back>
swap_need_kb() {
    local t f id new old sum=0 max=0 src
    for t in $1; do
        split_target "$t"
        f=$(t_main); new=$(size_kb "$WORK/$f"); old=$(size_kb "$(live_of "$f")")
        [ $new -gt $old ] && sum=$((sum + new - old)); [ $new -gt $max ] && max=$new
    done
    for id in $2; do
        f=$(recipe_file "$id") || continue
        new=$(size_kb "$WORK/$f"); old=$(size_kb "$LIB_DIR/$f")
        [ $new -gt $old ] && sum=$((sum + new - old)); [ $new -gt $max ] && max=$new
        [ "$id" = carplay-utils-converter ] && [ ! -e "$LIB_DIR/libev6aac.so" ] && sum=$((sum + $(size_kb "$PKG/files/libev6aac.so")))
    done
    for f in $3; do
        src=$BACKUP/$f; new=$(size_kb "$src"); old=$(size_kb "$(live_of "$f")")
        [ $new -gt $old ] && sum=$((sum + new - old)); [ $new -gt $max ] && max=$new
    done
    echo $((sum + max + 1024))
}

# ---------------------------------------------------------------- Leafia's lpatch recipes (the CarPlay libraries)
# recipes/<id>.recipe: byte-exact patches lpatch applies only when every original byte matches (it holds only hashes
# of the stock bytes and the new bytes). Each checks itself: PATCHABLE (the stock bytes: patched here), APPLIED
# (patched: ours when we recorded it), NATIVE (this firmware does it already; KR 260902's libCarPlayCore and
# libCarPlayUtils), anything else does not fit and is skipped. Leafia's order: the converter (libCarPlayUtils, which
# then needs libev6aac.so) first, then the audio formats, then the core. 0.1.37: the core has two recipes, the frame
# wait (carplay-core-frames-ef49c09b, only for the stock ef49c09b, which takes Wi-Fi sessions natively) listed before the Wi-Fi
# one (which says NATIVE on that stock file and MISMATCH on the file the frame wait wrote); one recipe at most writes a file.
RECIPE_IDS="carplay-utils-converter carplay-audio-formats carplay-core-frames-ef49c09b carplay-core-wifi"
# 0.1.37: recipes/gates, "<recipe id> <stock md5> <result md5>": lpatch checks only the bytes a recipe changes, so a recipe
# listed there is also built only from the stock file with exactly that whole-file md5, and must give exactly that result.
recipe_gate() {   # recipe_gate <id> <1|2>: the stock (1) or the result (2) md5 of the id's line; nothing when it has none
    local gi gs gr
    [ -f "$RECIPES/gates" ] || return 0
    while read -r gi gs gr || [ -n "$gi" ]; do
        case "$gi" in ''|'#'*) continue ;; esac
        [ "$gi" = "$1" ] || continue
        if [ "$2" = 1 ]; then echo "$gs"; else echo "$gr"; fi
        return 0
    done < "$RECIPES/gates"
    return 0
}
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
    local id f st live gs R_FILES=" "
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
                gs=$(recipe_gate "$id" 1)
                if [ -n "$gs" ] && [ "$(md5of "$live")" != "$gs" ]; then
                    log "recipe $id: $f is not the stock build this recipe is for (md5 $(md5of "$live"), it wants $gs): skipped"; continue
                fi
                case "$R_FILES" in *" $f "*) log "recipe $id: $f is taken by another recipe of this run: skipped"; continue ;; esac
                R_FILES="$R_FILES$f "
                [ -n "$gs" ] && log "recipe $id: $f is the stock build $gs: it will be patched"
                R_TODO="$R_TODO $id" ;;
            APPLIED)
                if has_line "$f $(md5of "$live")" "$APPLIED" && [ "$(md5of "$BACKUP/$f")" = "$(lookup "$STOCK_LIST" "$f")" ]; then
                    log "recipe $id: $f is patched already (ours)"
                else
                    log "recipe $id: $f is patched by something else and we have no stock copy: left alone"
                fi ;;
            NATIVE) log "recipe $id: this firmware's $f does it already: nothing to do" ;;
            MISMATCH)
                # 0.1.37: the stock file is NATIVE for this recipe, and what we see is that file with our other recipe on it
                if has_line "$f $(md5of "$live")" "$APPLIED" && [ -f "$BACKUP/$f" ] && [ "$(lp_state "$id" "$BACKUP/$f")" = NATIVE ]; then
                    log "recipe $id: this firmware's $f does it already (the file carries our other recipe): nothing to do"
                else
                    log "recipe $id: $f does not fit this firmware ($st): skipped"
                fi ;;
            *) log "recipe $id: $f does not fit this firmware ($st): skipped" ;;
        esac
    done
}
build_recipe() {   # build_recipe <id>: the patched copy into $WORK (lpatch writes it only when every byte matched)
    local f gr
    f=$(recipe_file "$1") || return 1
    mkdir -p "$WORK" || return 1
    rm -f "$WORK/$f"
    "$LPATCH" apply "$RECIPES/$1.recipe" "$LIB_DIR/$f" "$WORK/$f" >> "$LOG" 2>&1 && [ -s "$WORK/$f" ] &&
        [ "$(lp_state "$1" "$WORK/$f")" = APPLIED ] && {
            gr=$(recipe_gate "$1" 2)
            if [ -n "$gr" ] && [ "$(md5of "$WORK/$f")" != "$gr" ]; then
                log "recipe $1: the patched $f is $(md5of "$WORK/$f"), not the $gr it must be: not written"
            else
                log "built $f with recipe $1"; return 0
            fi
        }
    rm -f "$WORK/$f"
    return 1
}
apply_recipe() {   # apply_recipe <id>: (the converter first for the utils recipe) the copy into /system, checked
    local f live
    f=$(recipe_file "$1"); live=$LIB_DIR/$f
    if [ "$1" = carplay-utils-converter ] && [ ! -e "$LIB_DIR/libev6aac.so" ]; then
        j_ours libev6aac.so none "$CONV_SUM"
        put_file "$PKG/files/libev6aac.so" "$LIB_DIR/libev6aac.so" && [ "$(md5of "$LIB_DIR/libev6aac.so")" = "$CONV_SUM" ] ||
            { REASON="could not add $LIB_DIR/libev6aac.so"; return 1; }
        record "$ADDED" libev6aac.so "$CONV_SUM"
        j_wrote libev6aac.so "$CONV_SUM"
        log "OK: added libev6aac.so (the converter libCarPlayUtils forwards to)"
    fi
    j_ours "$f" "$(md5of "$live")" "$(md5of "$WORK/$f")"
    put_file "$WORK/$f" "$live" || { applied_mark "$f" "$(lookup "$STOCK_LIST" "$f")"; REASON="could not write $live"; return 1; }
    applied_mark "$f" "$(lookup "$STOCK_LIST" "$f")"
    j_wrote "$f" "$(md5of "$live")"
    [ "$(lp_state "$1" "$live")" = APPLIED ] || { REASON="$live does not check as patched after the write"; return 1; }
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
# 0.2.3 (CXARBN6Y, Ioniq 5, 2026-11-27): only an app whose files change in this run is stopped. Before, every app of
# HOLD_PKGS was stopped, also those whose files stayed as they were (the navigation app, while the cluster showed
# "check lane change assist", which uses its data). The owner of a file, by what the stock code names:
#  - the receiver library is loaded by HKMC_GPM only (HKMC_GPM's odex names it; no other app of the five does);
#  - the CarPlay libraries (CarPlayAndroid needs libCarPlay, libCarPlayAudio, libCarPlayCore, libCarPlayCoreUtils,
#    libCarPlayUtils) and the converter libCarPlayUtils forwards to are loaded by HKMC_DiPO only (its odex names
#    CarPlayAndroid; none of the other four does).
# No dependency between two apps was found (each library belongs to one app; the apps run in their own processes), so
# one app's change never stops another.
pkg_of_file() {
    case "$1" in
        HKMC_GPM.apk|HKMC_GPM.odex|libautoreceiver_infobank.so) echo com.google.android.projection.sink ;;
        HKMC_DiPO.apk|HKMC_DiPO.odex|libCarPlay*.so|libev6aac.so) echo com.daudio.app.dipo ;;
        Iap2ServerApp.apk|Iap2ServerApp.odex) echo com.tcc.iap2server ;;
        HKMC_Navi_ExSL.apk|HKMC_Navi_ExSL.odex) echo com.mnsoft.navi ;;
        PhoneProjection.apk|PhoneProjection.odex) echo com.daudio.app.phoneprojection ;;
        *) return 1 ;;
    esac
}
# restore_set [<files>]: the files restore_files / remove_added would write now (a live file that differs from its
# stock copy and is ours; an added file still ours), as words: what an uninstall, a lock or a rollback changes
restore_set() {
    local f s live got out=
    if [ -f "$STOCK_LIST" ]; then
        while read -r f s || [ -n "$f" ]; do
            [ -n "$f" ] && [ -n "$s" ] || continue
            [ -z "$1" ] || case " $1 " in *" $f "*) ;; *) continue ;; esac
            got=$(md5of "$(live_of "$f")")
            [ "$got" = "$s" ] && continue
            restorable "$f" "$got" && out="$out $f"
        done < "$STOCK_LIST"
    fi
    if [ -z "$1" ] && [ -f "$ADDED" ]; then
        while read -r f s || [ -n "$f" ]; do
            [ -n "$f" ] || continue
            live=$(live_of "$f")
            [ -e "$live" ] && [ "$(md5of "$live")" = "$s" ] && out="$out $f"
        done < "$ADDED"
    fi
    echo $out
}
# apps_hold <files that change in this step>: stops the enabled apps that own one of them; one log line per app
apps_hold() {
    local p f fl unknown= all=
    if ! android_up; then log "no app stopped: Android is not up"; return 0; fi
    for f in "$@"; do pkg_of_file "$f" >/dev/null || unknown="$unknown $f"; done
    [ -z "$unknown" ] || log "WARNING: no known owner app for:$unknown - every app is stopped"
    : >> "$HOLD_FILE" 2>/dev/null || { log "WARNING: cannot record stopped apps; not stopping them"; return 0; }
    for p in $HOLD_PKGS; do
        fl=
        if [ -n "$unknown" ]; then fl=" (owner of a file not known)"; else
            for f in "$@"; do [ "$(pkg_of_file "$f")" = "$p" ] && fl="$fl $f"; done
            [ -n "$fl" ] && fl=" ($fl changes)"
        fi
        if [ -z "$fl" ]; then log "not held $p (unchanged)"; continue; fi
        if has_line "$p" "$HOLD_FILE"; then log "held $p$fl: stopped by an earlier step, stays"; continue; fi
        pkg_enabled "$p" || { log "not held $p (absent, or disabled by the owner)"; continue; }
        echo "$p" >> "$HOLD_FILE"
        if pm disable "$p" </dev/null >/dev/null 2>&1; then log "held $p$fl: stopped for the file swap"; else log "WARNING: could not stop $p"; fi
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
# wireless.carplay.bt, carplay.*), Evergreen, 단풍 (danpung*), the Korean mod package (korea.projection), aa.usbwifi, an
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

# NEMESIS runs the installed package's preuninstall before an update too, with the new package staged already, from
# its "nemesis install --update" process. 0.1.8 (QA 2026-11-19 #5), three ways: the parent says "uninstall": a real
# uninstall, whatever is staged (a stage left by an interrupted install never turns it into nothing); it says
# "install": an update when our package is staged; it names neither (NEMESIS Manager's own process, an unreadable
# cmdline): the staged package decides, as before.
parent_cmdline() { cat /proc/$PPID/cmdline 2>/dev/null; }
is_update() {
    case "$(parent_cmdline)" in *uninstall*) return 1 ;; esac
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
# 0.1.8: from the files: every file we wrote (APPLIED) or added (ADDED) that is live as we wrote it, the targets'
# order first; an earlier version's files still in place count too (an update that changed nothing)
patched_list() {
    local t f s l seen=" " out=
    for t in $TARGETS; do
        split_target "$t"
        f=$(t_main); s=$(md5of "$(live_of "$f")")
        [ -n "$s" ] && has_line "$f $s" "$APPLIED" || continue
        out="$out,$(tag_of "$T_NAME")"; seen="$seen$f "
    done
    for l in "$APPLIED" "$ADDED"; do
        [ -f "$l" ] || continue
        while read -r f s || [ -n "$f" ]; do
            [ -n "$f" ] && [ -n "$s" ] || continue
            case "$seen" in *" $f "*) continue ;; esac
            [ "$(md5of "$(live_of "$f")")" = "$s" ] || continue
            seen="$seen$f "; out="$out,$(tag_of "${f%.apk}")"
        done < "$l"
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

# boot_check (the service, once per start): on a later boot than the install's, every file we wrote (the applied
# record: the rebuilt apps, the receiver library, the recipe libraries) is checked against /system. state=reboot
# becomes active when all are in place, or failed. 0.1.8 (QA 2026-11-19 #8): also state=active, at every boot: before,
# "active" was never looked at again, so after a firmware update put the stock apps back it stayed "active" for good.
# Now that says "firmware changed" (failed, in words for the menu; the records are made true to the new firmware).
boot_check() {
    local b f s miss= n=0 st old=
    st=$(status_get state)
    case "$st" in reboot|active) ;; *) return 0 ;; esac
    b=$(boot_token)
    [ -n "$b" ] && [ "$b" = "$(cat "$BOOT_FILE" 2>/dev/null)" ] && return 0
    WARN=$(status_get warn)
    if [ ! -f "$APPLIED" ]; then
        [ "$st" = reboot ] && write_status failed "after the reboot: no record of the patched files"
        return 0
    fi
    while read -r f s || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        [ "$(md5of "$(live_of "$f")")" = "$s" ] || miss="$miss $f"
    done < "$APPLIED"
    fw_changed && old=$(cat "$FP_FILE" 2>/dev/null) && fw_reconcile
    if [ -z "$miss" ] && [ $n -gt 0 ]; then
        [ "$st" = active ] && return 0
        write_status active ""
        log "boot: every patched file ($n) is in place after the reboot: active"
    elif [ -n "$old" ]; then
        write_status failed "펌웨어가 바뀌어 순정 앱이 새로 설치되었습니다 · 확장을 다시 설치해 주세요 (firmware changed; not patched:${miss:- none recorded})"
        log "boot: firmware changed ($old -> $(fp_now)): not the patched files:$miss"
        report boot-firmware-changed "$old -> $(fp_now):$miss"
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

# 0.3.5 / 0.1.9 (the owner 2026-11-19): the tamper lock the JMK MAP menu's daemon decides (its Integrity:
# /data/nemesis/jmk-updates/integrity, lock=0|1, text=). Sets ILOCK (1 or "") and ITEXT. Never this package's own call.
integrity_read() {
    ILOCK=; ITEXT=
    local k v
    [ -f "$R/data/nemesis/jmk-updates/integrity" ] || return 0
    while IFS='=' read -r k v || [ -n "$k" ]; do
        case "$k" in lock) [ "$v" = 1 ] && ILOCK=1 ;; text) ITEXT=$v ;; esac
    done < "$R/data/nemesis/jmk-updates/integrity"
}

# 0.1.17: the lock's hold, the one place that applies it: postinstall first of all (every install and update: NEMESIS,
# NEMESIS Manager, the MAP menu) and the settings service at its start. Before, only the service held the lock, once
# (put back, records dropped, LOCK_MARK written); an update while it said lock=1 was then a fresh install over the stock
# files, and the service NEMESIS starts after every update found the mark and did nothing: patched while locked.
# lock_hold: every file this package wrote or added goes back (restore_files: only what ours() says is ours, as an
# uninstall), the records go (the md5-checked stock copies stay in $BACKUP), state=locked with the lock's text, and only
# then the mark. 1 (records kept, no mark: the next start tries again) when a file could not be put back.
# lock_held: the mark, and nothing of ours recorded (a mark next to records is an earlier version's update over it).
LOCK_MARK=$STORE/integrity-locked
lock_held() { [ -f "$LOCK_MARK" ] && [ ! -f "$STOCK_LIST" ] && [ ! -f "$ADDED" ]; }
lock_hold() {
    local f s names=
    if [ -f "$STOCK_LIST" ] || [ -f "$ADDED" ]; then
        system_writable || { REASON="/system is read-only"; log "integrity lock: /system read-only, nothing put back"; return 1; }
        apps_hold $(restore_set)
        REASON=
        if ! restore_files || ! remove_added; then
            apps_release
            log "integrity lock: $REASON (the stock copies stay in $BACKUP)"
            report integrity-lock-failed "$REASON"
            return 1
        fi
        if [ -f "$STOCK_LIST" ]; then
            while read -r f s || [ -n "$f" ]; do case "$f" in *.apk) names="$names ${f%.apk}" ;; esac; done < "$STOCK_LIST"
        fi
        wipe_dalvik "$names"
        apps_release
        leafia_props_clear
        rm -f "$STOCK_LIST" "$APPLIED" "$ADDED"
        sync
        log "integrity lock: every stock file is back - reboot the head unit"
    fi
    : > "$LOCK_MARK"
    write_status locked "${ITEXT:-locked}"
    report integrity-locked "$ITEXT"
    return 0
}
