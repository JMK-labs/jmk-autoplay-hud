#!/system/bin/sh
# jmk-autoplay-hud settings service (NEMESIS [service], root, background; AGPL-3.0, see LICENSE and NOTICE.md).
#  - once Android is up: starts again any app an install run left stopped, and turns state=reboot into active (or
#    failed) when this is a later boot than the install's;
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
n=0
while ! android_up && [ $n -lt 120 ]; do sleep 5; n=$((n + 1)); done
apps_release
SET=
[ -f "$SET_FILE" ] && read -r SET < "$SET_FILE"
load_targets
boot_check
case "$(status_get state)" in reboot|active) apply_config force ;; esac
[ -n "$JMK_HUD_ONCE" ] && exit 0
while [ -f "$INSTALLED" ]; do
    sleep 5
    case "$(status_get state)" in reboot|active) apply_config ;; esac
done
exit 0
