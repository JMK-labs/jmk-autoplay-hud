#!/system/bin/sh
# jmk-autoplay-hud settings service (NEMESIS [service], root, background; AGPL-3.0, see LICENSE and NOTICE.md).
#  - once Android is up: starts again any app an install run left stopped, and on a later boot than the install's
#    checks every file it wrote: state=reboot becomes active (or failed), an active one whose files a firmware update
#    replaced says so (0.1.8);
#  - then the bridge from the JMK MAP menu's config (/data/local/tmp/jmk-autoplay-hud/config, key=value, written by the
#    menu's daemon) to the persist.leafia.* switches the patched apps read (scripts/common.sh knob_props): applied at
#    start and whenever the file changes (looked at every 5 s). Keys without a switch are ignored.
# JMK_HUD_ONCE=1 (tests): one pass, no loop.
PKG=${JMK_HUD_PKG:-/data/nemesis/apps/jmk-autoplay-hud}
[ -d "$PKG" ] || PKG=/data/nemesis/packages/jmk-autoplay-hud
. "$PKG/scripts/common.sh"
[ -f "$INSTALLED" ] || exit 0
svc_stop
echo $$ > "$STORE/svc.pid"
# 0.1.8: the log capped, copies a cut-off swap left beside the stock files removed
log_cap
clean_tmp
n=0
while ! android_up && [ $n -lt 120 ]; do sleep 5; n=$((n + 1)); done
apps_release
SET=
[ -f "$SET_FILE" ] && read -r SET < "$SET_FILE"
load_targets
# 0.1.25: an install cut off during its swap (state=installing: power or a kill, its journal run never ended) is run
# again: the files it wrote are ours by the made list, the stock copies are in $BACKUP or the archive
if [ "$(status_get state)" = installing ]; then
    log "boot: the last install was cut off during its swap: running it again"
    ( cd "$PKG" && sh scripts/postinstall.sh ) >> "$LOG" 2>&1
fi
boot_check
# 0.1.9 (the owner 2026-11-19): the tamper lock (the JMK MAP menu's daemon). While it says lock=1 every stock file goes
# back (ownership-checked, as an uninstall) and the state says its text; once it no longer does, the add-on is applied
# again (as a fresh install: its postinstall).
# 0.1.17: the hold is common.sh lock_hold, the same one postinstall runs first; held is the mark with nothing of ours
# recorded (a mark next to records: an update of an earlier version patched over it), the mark goes with a postinstall
# that applies.
integrity_read
if [ -n "$ILOCK" ]; then
    lock_held || lock_hold || log "boot: integrity lock not held yet: $REASON"
elif [ -f "$LOCK_MARK" ]; then
    log "boot: integrity lock lifted: applying the add-on again"
    ( cd "$PKG" && sh scripts/postinstall.sh ) >> "$LOG" 2>&1
fi
case "$(status_get state)" in reboot|active) apply_config force ;; esac
[ -n "$JMK_HUD_ONCE" ] && exit 0
while [ -f "$INSTALLED" ]; do
    sleep 5
    case "$(status_get state)" in reboot|active) apply_config ;; esac
done
exit 0
