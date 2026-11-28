#!/system/bin/sh
# jmk-autoplay-hud: the migration from the legacy (file-swapping) HUD to the LivePatch HUD (AGPL-3.0, see LICENSE and NOTICE.md).
# migrate.meta restore= / verify= run this from the UNPACKED zip, as root, while the legacy HUD is still installed.
#   legacy-restore.sh            put every stock file the legacy HUD replaced back (md5-checked), then verify
#   legacy-restore.sh --check    write nothing, print what is still ours
#   legacy-restore.sh --verify   write nothing, exit 0 only when no file of ours is left (legacy-verify.sh calls this)
# Self-contained: nothing is read from the installed legacy scripts (their record formats differ by version). It does not
# depend on the records either: every file a HUD version ever wrote (the five apps' apk + odex, infobank, the CarPlay libraries,
# the converter) is judged by what it IS: an odex by the code inside it (a profile's stock code = stock, a result = ours), an apk by
# a classes.dex entry (stock apks have none), a library by its profile line or recipe state (APPLIED / a known result = ours).
# The records (stock, applied, added, made, archive index) add evidence and the stock md5 when they are there. The stock copy of an
# edited file comes from the records, else from the legacy backup / archive directories and is accepted only when our own recipe
# or delta applied to it gives exactly the live file's md5 (an odex / apk: the same profile line). None matches = a failure.
# A file of the legacy HUD's is judged one way:
#   stock-ok   its md5 is the recorded stock md5 (or the added converter is gone)
#   restored   it was ours, the stock copy (md5-checked) went back
#   foreign    neither stock nor ours (a firmware update or another tool wrote it): left alone, as the legacy uninstall did
#   not-stock  still recorded as patched by us, but the stock copy cannot be put back or ours cannot be told: a failure
# Output: one line per file ("<state> <file> <md5> [<expected stock md5>]"), the last line "legacy-restore: ...".
# Exit: 0 restored (or every file stock after it), 10 nothing to do (the legacy HUD never edited anything),
#       1 a part failed or a file is not stock, 70 the step itself failed (/system not writable, no records readable).
here=${0%/*}
case "$here" in /*) ;; *) here=$(pwd)/$here ;; esac
MODE=restore
case "$1" in --check) MODE=check ;; --verify) MODE=verify ;; "") ;; *) echo "legacy-restore: unknown argument $1"; exit 70 ;; esac

ID=jmk-autoplay-hud
R=${JMK_HUD_TEST_ROOT:-}                       # a sandbox root for the Mac tests only; empty on the car
[ -n "$R" ] || export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -z "$JMK_LR_SHIMS" ] || . "$JMK_LR_SHIMS"    # tests: md5/getprop/pm shims (never set on the car)
STORE=$R/data/nemesis/$ID
STOCK_LIST=$STORE/stock
APPLIED=$STORE/applied
ADDED=$STORE/added
HOLD_FILE=$STORE/stopped
FP_FILE=$STORE/fingerprint
MADE=$R/data/nemesis/$ID.made
ARCHIVE=$R/data/nemesis/backups/$ID.stock
BACKUP=$R/data/nemesis/backups/$ID
LOG=$R/data/nemesis/$ID.log
KNOWN=$here/../tools/legacy-known               # (tests: JMK_LR_KNOWN) every result any legacy version wrote ("<file> <md5>"), shipped with this zip
OLD_JAR=$R/data/nemesis/apps/$ID/tools/codesum.jar   # the installed legacy HUD's own tool (judges an .apk by its classes.dex)
APP_DIR=$R/system/app
LIB_DIR=$R/system/lib
NEMESIS_BIN=$R/system/xbin/nemesis
HOLD_PKGS="com.google.android.projection.sink com.daudio.app.dipo com.tcc.iap2server com.mnsoft.navi com.daudio.app.phoneprojection"
[ -z "$R" ] || KNOWN=${JMK_LR_KNOWN:-$KNOWN}
WORK=$R/data/local/tmp/$ID.restore.$$
TOOLS=$here/../tools
[ -z "$R" ] || TOOLS=${JMK_LR_TOOLS:-$TOOLS}
LPATCH=$TOOLS/lpatch
[ -z "$R" ] || LPATCH=${JMK_LPATCH:-$LPATCH}
BYCODE=$TOOLS/patches/bycode
PATCHES=$TOOLS/patches
RECIPES=$TOOLS/recipes
CONV_RECIPE=$here/../files/carplay-utils-converter.recipe
CONV_SUM=badc26bd4c40a1c3e543b733a8ec5028       # the converter library the legacy HUD added
APPS="HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL PhoneProjection"
LIBS="libautoreceiver_infobank.so libCarPlayCore.so libCarPlayAudio.so libCarPlayUtils.so libev6aac.so"
trap 'rm -rf "$WORK" 2>/dev/null' 0

log() { echo "$1"; mkdir -p "${LOG%/*}" 2>/dev/null; echo "$(date) legacy-restore: $1" >> "$LOG" 2>/dev/null; true; }
say() { echo "$1"; echo "$(date) legacy-restore: $1" >> "$LOG" 2>/dev/null; true; }
md5of() { set -- $(md5 "$1" 2>/dev/null); echo "$1"; }
live_of() { case "$1" in *.so) echo "$LIB_DIR/$1" ;; *) echo "$APP_DIR/$1" ;; esac; }
has_line() {
    local l
    [ -f "$2" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do [ "$l" = "$1" ] && return 0; done < "$2"
    return 1
}
lookup() {   # lookup <list> <file>: the md5 a "<file> <md5>" list holds for that file
    local f s
    [ -f "$1" ] || return 1
    while read -r f s _ || [ -n "$f" ]; do [ "$f" = "$2" ] && [ -n "$s" ] && { echo "$s"; return 0; }; done < "$1"
    return 1
}
in_list() { has_line "$2 $3" "$1"; }

# ---------------------------------------------------------------- which files, and whose they are
# candidates: every file a HUD version ever wrote (the fixed names) and every name any record of the legacy HUD holds
candidates() {
    local l f s a out=" "
    for a in $APPS; do out="$out$a.apk $a.odex "; done
    for f in $LIBS; do out="$out$f "; done
    for l in "$STOCK_LIST" "$APPLIED" "$ADDED" "$MADE"; do
        [ -f "$l" ] || continue
        while read -r f s _ || [ -n "$f" ]; do
            [ -n "$f" ] || continue
            case "$f" in \#*) continue ;; esac
            case "$out" in *" $f "*) ;; *) out="$out$f " ;; esac
        done < "$l"
    done
    echo $out
}
# the stock md5 of a file: the record, else the archive's copy indexed for this firmware (cars whose record was lost)
fp_now() { getprop ro.build.fingerprint; }
fw_changed() { [ -f "$FP_FILE" ] && [ "$(cat "$FP_FILE" 2>/dev/null)" != "$(fp_now)" ]; }
stock_md5() {
    local f s p want=
    lookup "$STOCK_LIST" "$1" && return 0
    [ -f "$ARCHIVE/index" ] || return 1
    while read -r f s p || [ -n "$f" ]; do [ "$f" = "$1" ] && [ "$p" = "$(fp_now)" ] && want=$s; done < "$ARCHIVE/index"
    [ -n "$want" ] && [ "$(md5of "$ARCHIVE/$1.$want")" = "$want" ] && { echo "$want"; return 0; }
    return 1
}
# the stock copy's path (md5-checked): the backup directory, else the archive
stock_copy() {   # stock_copy <file> <md5>
    [ "$(md5of "$BACKUP/$1")" = "$2" ] && { echo "$BACKUP/$1"; return 0; }
    [ "$(md5of "$ARCHIVE/$1.$2")" = "$2" ] && { echo "$ARCHIVE/$1.$2"; return 0; }
    return 1
}
# a code sum of an .apk's classes.dex: asked of the installed legacy HUD's own tool when it is still there
apk_dex() {
    local pid n out= f
    local jar=$TOOLS/codesum.jar
    [ -f "$jar" ] || jar=$OLD_JAR
    [ -f "$jar" ] || return 1
    mkdir -p "$WORK" 2>/dev/null
    f=$WORK/codesum.out; rm -f "$f"
    CLASSPATH=$jar app_process /system/bin jmkhud.CodeSum apkdex "$1" > "$f" 2>/dev/null &
    pid=$!; n=0
    while kill -0 "$pid" 2>/dev/null && [ $n -lt 20 ]; do sleep 1; n=$((n + 1)); done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    [ -f "$f" ] && read -r out < "$f"
    rm -f "$f"
    out=${out#dex=}
    [ -n "$out" ] && [ "$out" != none ] && echo "$out"
}
# ours_file <file> <live md5>: a result of any legacy version (records, made list, shipped known list, or an apk whose
# classes.dex is a known by-code result). An odex follows its apk (our dexopt writes it: its md5 is not known before).
ours_file() {
    local f=$1 g=$2 apk a d
    case "$f" in
        *.odex)
            [ -n "$g" ] && in_list "$MADE" "$f" "$g" && return 0
            fw_changed && return 1       # another firmware: only its own md5 counts
            apk=${f%.odex}.apk
            a=$(md5of "$(live_of "$apk")")
            [ -n "$a" ] || return 1
            in_list "$APPLIED" "$apk" "$a" && return 0
            in_list "$MADE" "$apk" "$a" && return 0
            in_list "$KNOWN" "$apk" "$a" && return 0
            ours_apk_dex "$apk" && return 0
            [ -f "$FP_FILE" ] && [ "$a" = "$(lookup "$STOCK_LIST" "$apk")" ] ;;     # the apk is already put back, its odex not yet
        *)  [ -n "$g" ] || return 1
            in_list "$APPLIED" "$f" "$g" && return 0
            in_list "$MADE" "$f" "$g" && return 0
            in_list "$KNOWN" "$f" "$g" && return 0
            ours_apk_dex "$f" ;;
    esac
}
ours_apk_dex() {
    local base d
    case "$1" in *.apk) ;; *) return 1 ;; esac
    base=${1%.apk}
    grep -q "^$base\.dex " "$KNOWN" 2>/dev/null || return 1
    d=$(apk_dex "$(live_of "$1")") || return 1
    has_line "$base.dex $d" "$KNOWN"
}

# ---------------------------------------------------------------- the judgement by what a file IS (no writes)
lp_state() {   # lp_state <recipe file> <library>: PATCHABLE | APPLIED | NATIVE | MISMATCH | MISSING | ERROR
    local out w st=ERROR
    [ -f "$LPATCH" ] && [ -f "$1" ] && [ -f "$2" ] || { echo ERROR; return 0; }
    chmod 0755 "$LPATCH" 2>/dev/null
    out=$("$LPATCH" check "$1" "$2" 2>&1)
    set -f; for w in $out; do case "$w" in status=*) st=${w#status=} ;; esac; done; set +f
    echo "$st"
}
cs_run() {   # cs_run <args>: the one line jmkhud.CodeSum prints (the jar of this zip, app_process as the legacy HUD runs it; the ARM lpatch has no odexdex); 20 s guard, a second try with a private ANDROID_DATA
    local jar=$TOOLS/codesum.jar pid n out= f t
    [ -f "$jar" ] || return 0
    mkdir -p "$WORK/var/dalvik-cache" 2>/dev/null
    for t in 1 2; do
        rm -f "$WORK/cs.out"
        if [ $t = 2 ]; then ANDROID_DATA=$WORK/var; export ANDROID_DATA; fi
        CLASSPATH=$jar app_process /system/bin jmkhud.CodeSum "$@" > "$WORK/cs.out" 2>/dev/null &
        pid=$!; n=0
        while kill -0 "$pid" 2>/dev/null && [ $n -lt 20 ]; do sleep 1; n=$((n + 1)); done
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
        out=; [ -f "$WORK/cs.out" ] && read -r out < "$WORK/cs.out"
        [ -n "$out" ] && break
    done
    echo "$out"
}
dex_md5() {   # dex_md5 <odex>: the md5 of the dex inside one odex
    local out
    rm -f "$WORK/x.dex"
    out=$(cs_run extract "$1" "$WORK/x.dex")
    case "$out" in code=?*) [ "$out" != code=none ] && [ -s "$WORK/x.dex" ] && { echo "${out#code=}"; return 0; } ;; esac
    return 1
}
LIVECODES=
live_code() {   # live_code <App>: the code md5 of the live odex, all five read by ONE run per judgement
    local a files= w
    if [ -z "$LIVECODES" ]; then
        for a in $APPS; do [ -f "$APP_DIR/$a.odex" ] && files="$files $APP_DIR/$a.odex"; done
        mkdir -p "$WORK" 2>/dev/null
        LIVECODES=" $([ -n "$files" ] && cs_run $files) "
    fi
    for w in $LIVECODES; do case "$w" in "$1.code="*) w=${w#*=}; [ "$w" != none ] && echo "$w"; return 0 ;; esac; done
    return 1
}
mf_hit() {   # mf_hit <app|file> <name> <4 stock | 6 result> <md5>: some profile line of that name has that md5 in that column
    local d p k n c x w
    for d in "$BYCODE"/*/manifest; do
        [ -f "$d" ] || continue
        while read -r p k n c x w || [ -n "$p" ]; do
            case "$p" in 2_tbt|3_bridge) ;; *) continue ;; esac
            [ "$k" = "$1" ] && [ "$n" = "$2" ] || continue
            if [ "$3" = 4 ]; then [ "$c" = "$4" ] && return 0; else [ "$w" = "$4" ] && return 0; fi
        done < "$d"
    done
    return 1
}
recipes_of() {   # recipes_of <library>: the recipe files that name it
    local r k v rest
    for r in "$RECIPES"/*.recipe "$CONV_RECIPE"; do
        [ -f "$r" ] || continue
        while read -r k v rest || [ -n "$k" ]; do
            if [ "$k" = file ]; then [ "${v##*/}" = "$1" ] && echo "$r"; break; fi
        done < "$r"
    done
}
derived_state() {   # derived_state <file> <live path> <live md5>: STOCK | OURS | UNKNOWN | NONE, from the file itself
    local f=$1 live=$2 g=$3 m r st applied= fine=
    [ -n "$g" ] || { echo NONE; return 0; }
    case "$f" in
        *.apk)
            in_list "$KNOWN" "$f" "$g" && { echo OURS; return 0; }
            grep -q "classes.dex" "$live" 2>/dev/null && { echo OURS; return 0; }   # a stock apk of this firmware has no classes.dex: the code is in its odex
            echo STOCK ;;
        *.odex)
            m=$(live_code "${f%.odex}") || { echo UNKNOWN; return 0; }
            if mf_hit app "${f%.odex}" 4 "$m"; then echo STOCK
            elif mf_hit app "${f%.odex}" 6 "$m" || has_line "${f%.odex}.dex $m" "$KNOWN"; then echo OURS
            else echo UNKNOWN; fi ;;
        libev6aac.so) if [ "$g" = "$CONV_SUM" ]; then echo OURS; else echo UNKNOWN; fi ;;
        *.so)
            in_list "$KNOWN" "$f" "$g" && { echo OURS; return 0; }
            mf_hit file "$f" 6 "$g" && { echo OURS; return 0; }
            mf_hit file "$f" 4 "$g" && { echo STOCK; return 0; }
            for r in $(recipes_of "$f"); do
                st=$(lp_state "$r" "$live")
                case "$st" in APPLIED) applied=1 ;; PATCHABLE|NATIVE) fine=1 ;; esac
            done
            if [ -n "$applied" ]; then echo OURS; elif [ -n "$fine" ]; then echo STOCK; else echo UNKNOWN; fi ;;
        *) echo UNKNOWN ;;
    esac
}
# accept_stock <file> <copy> <copy md5> <live path> <live md5>: this copy is the stock file of the live one, proved with our own data
accept_stock() {
    local f=$1 c=$2 m=$3 live=$4 g=$5 cm lm d p k n cc x w r y
    case "$f" in
        *.apk) grep -q "classes.dex" "$c" 2>/dev/null && return 1; return 0 ;;
        *.odex)
            fw_changed && [ ! -f "$ARCHIVE/index" ] && return 1
            case "$c" in "$ARCHIVE"/*) has_line "$f $m $(fp_now)" "$ARCHIVE/index" || return 1 ;; esac   # an odex carries its framework's checksums: this firmware's copies only
            cm=$(dex_md5 "$c") || return 1; lm=$(live_code "${f%.odex}") || return 1
            for d in "$BYCODE"/*/manifest; do
                [ -f "$d" ] || continue
                while read -r p k n cc x w || [ -n "$p" ]; do
                    case "$p" in 2_tbt|3_bridge) ;; *) continue ;; esac
                    [ "$k" = app ] && [ "$n" = "${f%.odex}" ] && [ "$cc" = "$cm" ] && [ "$w" = "$lm" ] && return 0
                done < "$d"
            done
            return 1 ;;
        libev6aac.so) return 1 ;;
        *.so)
            mkdir -p "$WORK" 2>/dev/null; y=$WORK/y.so
            for d in "$BYCODE"/*/manifest; do
                [ -f "$d" ] || continue
                while read -r p k n cc x w || [ -n "$p" ]; do
                    case "$p" in 2_tbt|3_bridge) ;; *) continue ;; esac
                    [ "$k" = file ] && [ "$n" = "$f" ] && [ "$cc" = "$m" ] && [ "$w" = "$g" ] || continue
                    rm -f "$y"; "$LPATCH" delta "$PATCHES/$x" "$c" "$y" >/dev/null 2>&1 && [ "$(md5of "$y")" = "$g" ] && return 0
                done < "$d"
            done
            for r in $(recipes_of "$f"); do
                [ "$(lp_state "$r" "$c")" = PATCHABLE ] || continue
                rm -f "$y"; "$LPATCH" apply "$r" "$c" "$y" >/dev/null 2>&1 && [ "$(md5of "$y")" = "$g" ] && return 0
            done
            return 1 ;;
    esac
    return 1
}
derive_stock() {   # derive_stock <file> <live path> <live md5>: "<md5>@<path>" of an accepted copy in the legacy backup / archive directories
    local f=$1 live=$2 g=$3 c m
    for c in "$BACKUP/$f" "$ARCHIVE/$f".*; do
        [ -f "$c" ] || continue
        m=$(md5of "$c"); [ -n "$m" ] || continue
        case "$c" in "$ARCHIVE"/*) [ "${c##*.}" = "$m" ] || continue ;; esac     # an archive copy is named by its md5: a damaged one is skipped
        if accept_stock "$f" "$c" "$m" "$live" "$g"; then echo "$m@$c"; return 0; fi
    done
    return 1
}
DERIVED=" "
derived_get() { local w; for w in $DERIVED; do case "$w" in "$1@"*) echo "${w#*@}"; return 0 ;; esac; done; return 1; }   # "<md5>@<path>"

# judge: fills TODO (words, apks first), BAD (words), and prints one line per file
TODO=; BAD=; N_OK=0; N_FOREIGN=0
judge() {
    local f live g s ds dv isours apks= odex= libs= added= kind
    TODO=; BAD=; N_OK=0; N_FOREIGN=0; DERIVED=" "; LIVECODES=
    for f in $(candidates); do
        live=$(live_of "$f"); g=$(md5of "$live")
        if [ -f "$ADDED" ] && lookup "$ADDED" "$f" >/dev/null; then
            # a file we added: ours while it still has the recorded md5, gone is the stock state
            if [ -z "$g" ]; then echo "stock-ok $f (not there)"; N_OK=$((N_OK + 1))
            elif [ "$g" = "$(lookup "$ADDED" "$f")" ]; then echo "ours $f $g (added by the legacy HUD, will be removed)"; added="$added $f"
            else echo "foreign $f $g (not the file the legacy HUD added)"; N_FOREIGN=$((N_FOREIGN + 1)); fi
            continue
        fi
        if [ "$f" = libev6aac.so ]; then
            # no record of it: the converter is ours when it is the build we shipped
            if [ "$g" = "$CONV_SUM" ]; then echo "ours $f $g (the converter the legacy HUD added, no record: will be removed)"; added="$added $f"
            elif [ -n "$g" ]; then echo "foreign $f $g (not the converter the legacy HUD added)"; N_FOREIGN=$((N_FOREIGN + 1)); fi
            continue
        fi
        s=$(stock_md5 "$f")
        ds=$(derived_state "$f" "$live" "$g")
        [ -n "$g" ] || [ -n "$s" ] || continue                  # not there and never recorded: nothing to judge
        if [ -n "$s" ] && [ "$g" = "$s" ]; then echo "stock-ok $f $g"; N_OK=$((N_OK + 1)); continue; fi
        isours=
        if [ -z "$g" ]; then isours=1; elif ours_file "$f" "$g" || [ "$ds" = OURS ]; then isours=1; fi
        if [ -n "$isours" ]; then
            if [ -n "$s" ] && stock_copy "$f" "$s" >/dev/null; then
                echo "ours $f ${g:-missing} (stock $s: copy kept, will be put back)"
            elif dv=$(derive_stock "$f" "$live" "$g") && [ -n "$dv" ]; then
                DERIVED="$DERIVED$f@$dv "
                echo "ours $f ${g:-missing} (stock ${dv%%@*}: copy ${dv#*@} proved by our own data, will be put back)"
            else
                echo "not-stock $f ${g:-missing} (ours, judged by $ds${s:+, recorded stock $s}: no stock copy in the records, the backup or the archive gives this file with our recipe or delta)"
                BAD="$BAD $f"; continue
            fi
            case "$f" in *.apk) apks="$apks $f" ;; *.odex) odex="$odex $f" ;; *) libs="$libs $f" ;; esac
        elif [ -n "$s" ] && [ -f "$STOCK_LIST" ] && lookup "$STOCK_LIST" "$f" >/dev/null && ! fw_changed; then
            # recorded as patched by us on this firmware, yet not stock and none of our results: cannot be told
            echo "not-stock $f $g (recorded as patched by us, but not stock $s and not a result we know)"; BAD="$BAD $f"
        elif [ "$ds" = STOCK ] && [ -z "$s" ]; then
            echo "stock-ok $f $g (no record: judged by the code / profile state)"; N_OK=$((N_OK + 1))
        else
            echo "foreign $f $g (${s:+not stock $s, }not ours: a firmware update or another tool wrote it; left alone)"; N_FOREIGN=$((N_FOREIGN + 1))
        fi
    done
    TODO="$apks$odex$libs$added"        # an odex follows its apk
}

# ---------------------------------------------------------------- the writes
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
system_writable() {
    system_rw && return 0
    say "/system is read-only: asking NEMESIS for read-write"
    "$NEMESIS_BIN" remount rw >/dev/null 2>&1
    system_rw
}
put_file() {
    local tmp=$2.jmkhud
    rm -f "$tmp" 2>/dev/null
    cp "$1" "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    cmp "$1" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp" 2>/dev/null; return 1; }
    chmod 0644 "$tmp" 2>/dev/null
    chown 0.0 "$tmp" 2>/dev/null
    mv "$tmp" "$2" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    [ -x "$R/system/bin/restorecon" ] && restorecon "$2" 2>/dev/null
    cmp "$1" "$2" >/dev/null 2>&1
}
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
android_up() { [ "$(getprop sys.boot_completed)" = 1 ]; }
pkg_enabled() {
    local l
    for l in $(pm list packages -e "$1" </dev/null 2>/dev/null); do [ "$l" = "package:$1" ] && return 0; done
    return 1
}
# hold only the apps whose files go back (one log line per app); a file with no known owner stops every app
HELD=
hold_apps() {
    local p f fl unknown=
    android_up || { say "no app stopped: Android is not up"; return 0; }
    for f in "$@"; do pkg_of_file "$f" >/dev/null || unknown="$unknown $f"; done
    [ -z "$unknown" ] || say "no known owner app for:$unknown - every app is stopped"
    for p in $HOLD_PKGS; do
        fl=
        if [ -n "$unknown" ]; then fl=" (owner of a file not known)"; else
            for f in "$@"; do [ "$(pkg_of_file "$f")" = "$p" ] && fl="$fl $f"; done
            [ -n "$fl" ] && fl=" ($fl changes)"
        fi
        if [ -z "$fl" ]; then say "not held $p (unchanged)"; continue; fi
        pkg_enabled "$p" || { say "not held $p (absent, or disabled by the owner)"; continue; }
        if pm disable "$p" </dev/null >/dev/null 2>&1; then HELD="$HELD $p"; say "held $p$fl: stopped for the file swap"; else say "WARNING: could not stop $p"; fi
    done
}
release_apps() {
    local p
    for p in $HELD; do
        if pm enable "$p" </dev/null >/dev/null 2>&1; then say "started $p again"; else say "WARNING: could not start $p again (pm enable $p)"; FAILED="$FAILED enable:$p"; fi
    done
    HELD=
}
wipe_dalvik() {   # best effort: root without capabilities (over adb) cannot; the boot rebuilds a stale entry
    local d n e
    for d in "$R/data/dalvik-cache" "$R/data/dalvik-cache/arm" "$R/cache/dalvik-cache"; do
        [ -d "$d" ] || continue
        for n in $1; do
            for e in "$d"/*"@$n.apk@"*; do [ -e "$e" ] && rm -f "$e" 2>/dev/null; done
        done
    done
    return 0
}

# ---------------------------------------------------------------- main
judge
if [ "$MODE" != restore ]; then
    if [ -z "$TODO" ] && [ -z "$BAD" ]; then echo "legacy-restore: stock (${N_OK} stock, ${N_FOREIGN} foreign)"; exit 0; fi
    echo "legacy-restore: not stock: to put back:${TODO:- none}; cannot:${BAD:- none}"
    exit 1
fi
if [ -z "$TODO" ] && [ -z "$BAD" ]; then
    echo "legacy-restore: nothing to do (${N_OK} stock, ${N_FOREIGN} foreign)"
    exit 10
fi
FAILED=
if [ -n "$BAD" ]; then
    say "FAIL: not put back:$BAD - the runner refuses this car"
    echo "legacy-restore: failed: cannot put back:$BAD"
    exit 1
fi
system_writable || { echo "legacy-restore: failed: /system is read-only and NEMESIS could not make it writable"; exit 70; }
hold_apps $TODO
names=
for f in $TODO; do
    case "$f" in
        libev6aac.so)
            rm -f "$(live_of "$f")" 2>/dev/null
            if [ -e "$(live_of "$f")" ]; then say "FAIL: could not remove $f"; FAILED="$FAILED $f"; else say "removed $f"; fi ;;
        *)
            if dv=$(derived_get "$f"); then s=${dv%%@*}; src=${dv#*@}; else s=$(stock_md5 "$f"); src=$(stock_copy "$f" "$s"); fi
            if [ -n "$src" ] && put_file "$src" "$(live_of "$f")" && [ "$(md5of "$(live_of "$f")")" = "$s" ]; then
                say "restored $f (stock $s)"
                case "$f" in *.apk) names="$names ${f%.apk}" ;; esac
            else
                say "FAIL: could not put back $f"; FAILED="$FAILED $f"
            fi ;;
    esac
done
wipe_dalvik "$names"
release_apps
sync
rm -rf "$WORK" 2>/dev/null
# the verification: every file stock (or foreign), nothing left to put back
judge >/dev/null
if [ -n "$FAILED" ] || [ -n "$TODO" ] || [ -n "$BAD" ]; then
    echo "legacy-restore: failed:${FAILED:- }still ours:${TODO:- none}; not stock:${BAD:- none}"
    exit 1
fi
echo "legacy-restore: restored; every file is stock (${N_OK} stock, ${N_FOREIGN} foreign)"
exit 0
