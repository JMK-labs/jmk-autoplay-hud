#!/system/bin/sh
# jmk-autoplay-hud preuninstall (LivePatch build; AGPL-3.0, see LICENSE and NOTICE.md). LivePatch takes the files down at the next boot (09-LivePatch 1): nothing to put back here.
# Stops the settings service, clears the persist.leafia.* switches and removes our state. An update runs this too (the new postinstall writes the state again).
. ./scripts/lp-common.sh
. ./scripts/lp-settings.sh
. ./scripts/lp-status.sh
log "preuninstall $ID $VER (LivePatch)"
if [ -f "$STORE/svc.pid" ]; then
    read -r pid < "$STORE/svc.pid" || pid=
    case "$pid" in ''|*[!0-9]*) ;; *) grep -q 'svc/hud.sh' "/proc/$pid/cmdline" 2>/dev/null && kill "$pid" 2>/dev/null ;; esac
    rm -f "$STORE/svc.pid"
fi
leafia_props_clear
rm -f "$STORE/installed" "$STATUS" "$STATUS.tmp" "$BOOT_FILE"
rmdir "$STORE" 2>/dev/null
log "uninstalled: LivePatch shows the stock files again after the next reboot"
exit 0
