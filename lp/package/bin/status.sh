#!/system/bin/sh
# jmk-autoplay-hud (LivePatch build): what is in place, for adb (sh /data/nemesis/apps/jmk-autoplay-hud/bin/status.sh). Read only.
PKG=${0%/bin/*}
[ "$PKG" = "$0" ] && PKG=.
PKG=$(cd "$PKG" && pwd)
. "$PKG/scripts/lp-common.sh"
. "$PKG/scripts/lp-settings.sh"
. "$PKG/scripts/lp-status.sh"
echo "id=$ID ver=$VER"
echo "product=$(getprop ro.build.product)"
if [ -f "$STATUS" ]; then while IFS= read -r l || [ -n "$l" ]; do echo "status: $l"; done < "$STATUS"; else echo "status: none"; fi
echo "profile: $(lp_profile)"
echo "converter: $(sh "$PKG/scripts/converter-check.sh")"
echo "livepatch:"; "$NEMESIS_BIN" livepatch status 2>&1
for p in $LEAFIA_PROPS; do echo "$p=$(getprop "$p")"; done
if [ -f "$CONF" ]; then echo "config: $CONF"; else echo "config: none (defaults)"; fi
exit 0
