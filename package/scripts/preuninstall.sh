#!/system/bin/sh
# jmk-autoplay-hud preuninstall (AGPL-3.0, see LICENSE and NOTICE.md). Stops the settings service. On a real uninstall
# every stock file goes back byte-identical (md5-checked against the record of the install: the apps, their odex, the
# receiver library, the recipe libraries), the converter we added goes, the dalvik-cache entries are removed where root
# may (best effort, never a reason to stop), the persist.leafia.* switches are cleared and our state goes. A file that
# cannot be put back keeps the stock copies and the state (state=failed, exit 1). NEMESIS runs this before every
# update too: then the patched files stay (the new postinstall finds them in place).
. ./scripts/common.sh
log "preuninstall $ID $VER"
svc_stop
if is_update; then
    log "update: the patched files stay (the new postinstall checks them)"
    exit 0
fi
SET=
[ -f "$SET_FILE" ] && read -r SET < "$SET_FILE"
load_targets
WARN=
if [ -f "$STOCK_LIST" ] || [ -f "$ADDED" ]; then
    system_writable || {
        write_status failed "uninstall: /system is read-only and NEMESIS could not make it writable"
        log "FAIL: /system is read-only: nothing put back"
        report preuninstall-system-ro "$(grep ' /system ' /proc/mounts)"
        exit 1
    }
    apps_hold
    REASON=
    if ! restore_files || ! remove_added; then
        apps_release
        write_status failed "uninstall: $REASON (the stock copies stay in $BACKUP)"
        log "FAIL: uninstall: $REASON - the stock copies stay in $BACKUP"
        report preuninstall-failed "$REASON"
        exit 1
    fi
    names=
    if [ -f "$STOCK_LIST" ]; then
        while read -r f s || [ -n "$f" ]; do case "$f" in *.apk) names="$names ${f%.apk}" ;; esac; done < "$STOCK_LIST"
    fi
    wipe_dalvik "$names"
    apps_release
    sync
fi
leafia_props_clear
rm -rf "$BACKUP" "$WORK"
rm -f "$STOCK_LIST" "$APPLIED" "$ADDED" "$SET_FILE" "$BOOT_FILE" "$STATUS" "$STATUS.tmp" "$INSTALLED" "$STORE/svc.pid"
[ -f "$HOLD_FILE" ] && log "WARNING: still stopped: $(cat "$HOLD_FILE") (start them with pm enable)"
rmdir "$STORE" 2>/dev/null
log "uninstalled: every stock file is back${WARN:+ ($WARN)} - reboot the head unit"
exit 0
