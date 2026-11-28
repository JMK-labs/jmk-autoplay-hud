#!/system/bin/sh
# jmk-autoplay-hud settings service (LivePatch build; NEMESIS [service], root, background; AGPL-3.0, see LICENSE and NOTICE.md).
#  - once Android is up: reads what LivePatch holds (`nemesis livepatch status`) and the profile this unit's stock code fits, writes the status file
#    (state locked|reboot|active|failed), reports a refusal once per version and category;
#  - then the bridge from the JMK MAP menu's config to the persist.leafia.* switches: applied at start and whenever the file changes (looked at every 5 s).
# Nothing in /system is written here: LivePatch holds the files. Safe mode (safe=1) = stock files: report and do nothing else.
# JMK_HUD_ONCE=1 (tests): one pass, no loop.
PKG=${JMK_HUD_PKG:-/data/nemesis/apps/jmk-autoplay-hud}
[ -d "$PKG" ] || PKG=/data/nemesis/packages/jmk-autoplay-hud
. "$PKG/scripts/lp-common.sh"
. "$PKG/scripts/lp-settings.sh"
. "$PKG/scripts/lp-status.sh"
[ -f "$STORE/installed" ] || exit 0
SVC_PID=$STORE/svc.pid
echo $$ > "$SVC_PID"
n=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ $n -lt 120 ]; do sleep 5; n=$((n + 1)); done
decide
write_status "$STATE" "$REASON"
log "boot: state=$STATE set=${PROFILE:-none} patched=${PATCHED:-none}${REASON:+ ($REASON)}"
case "$STATE" in
    locked) report boot-no-profile "$(getprop ro.build.product)" ;;
    failed) report boot-failed "$REASON" ;;
esac
[ "$SAFE" = 1 ] && { [ -n "$JMK_HUD_ONCE" ] || while [ -f "$STORE/installed" ]; do sleep 60; done; exit 0; }
case "$STATE" in reboot|active) apply_config "$PROFILE" force ;; esac
[ -n "$JMK_HUD_ONCE" ] && exit 0
while [ -f "$STORE/installed" ]; do
    sleep 5
    case "$STATE" in reboot|active) apply_config "$PROFILE" ;; esac
done
exit 0
