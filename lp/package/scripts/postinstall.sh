#!/system/bin/sh
# jmk-autoplay-hud postinstall (LivePatch build; AGPL-3.0, see LICENSE and NOTICE.md). LivePatch has ported the files already (tools/hud-step, one step per target) and mounts them at the
# next boot; nothing in /system is written here. This only: marks the install (state=reboot until another boot), writes the first status, applies the menu's settings.
. ./scripts/lp-common.sh
. ./scripts/lp-settings.sh
. ./scripts/lp-status.sh
PKG=$(cd "$PKG" && pwd)
log "postinstall $ID $VER (LivePatch)"
mkdir -p "$STORE" 2>/dev/null
: > "$STORE/installed"
boot_token > "$BOOT_FILE" 2>/dev/null
decide
ST=$STATE
case "$STATE" in active|reboot|"") ST=reboot ;; esac   # just installed: the mount happens at the next boot
write_status "$ST" "$REASON"
log "postinstall: state=$ST set=${PROFILE:-none}${REASON:+ ($REASON)} - reboot to apply"
case "$STATE" in active|reboot|"") apply_config "$PROFILE" force ;; esac
exit 0
