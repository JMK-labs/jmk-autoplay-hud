#!/system/bin/sh
# jmk-autoplay-hud postinstall (AGPL-3.0, see LICENSE and NOTICE.md). Leafia's parts 2_tbt (projection.tbt: HKMC_GPM,
# HKMC_Navi_ExSL, libautoreceiver_infobank.so) and 3_bridge (the CarPlay Bluetooth bridge: Iap2ServerApp, HKMC_DiPO,
# and on the Korean set PhoneProjection), plus the CarPlay library recipes of 3_bridge/4_audio:
#  1. the patch set for this car, and every target's stock md5 checked before anything is written: a file that is
#     neither the expected stock one nor ours leaves the car as it is (state=locked, the reason names the file); each
#     recipe checks its own library and is skipped when it does not fit;
#  2. every file rebuilt from the car's own stock files into $WORK (Leafia's lpatch; each result md5-checked);
#  3. stock copies into $BACKUP (md5-checked), then the files go in (beside + rename), odex rewritten, dalvik-cache
#     best effort; any failure puts every stock file back (state=failed);
#  4. state=reboot: the head unit must restart before the apps run the new code (the settings service then sees the
#     files on the next boot and writes state=active).
# An update with the same patches finds every file in place and changes nothing.
. ./scripts/common.sh
log "postinstall $ID $VER"
mkdir -p "$STORE" "$BACKUP" && chmod 0700 "$STORE" "$BACKUP"
: > "$INSTALLED"
prev=$(status_get state)
SET=

lock() {
    write_status locked "$1"
    log "locked: $1 (nothing changed)"
    [ -d "$R/data/nemesis/backup/projection.tbt" ] && log "note: /data/nemesis/backup/projection.tbt (the snapshot of Leafia / projection.tbt) is still there: its uninstall may not have finished"
    report postinstall-locked "$1; product $(getprop ro.build.product); live $(live_sums)"
    exit 0
}
fail() {   # nothing of this run is left in /system
    rm -rf "$WORK"
    write_status failed "$1"
    log "FAIL: $1"
    report postinstall-failed "$1"
    [ -z "$(patched_list)" ] && rm -f "$INSTALLED"
    exit 1
}
rollback() {   # $1 = why: every stock file back, the added converter gone, then state=failed
    why=$1
    log "FAIL: $why - putting the stock files back"
    REASON=
    if restore_files && remove_added; then
        wipe_dalvik "$(app_names)"
        apps_release
        fail "$why (the stock files are back)"
    fi
    apps_release
    rm -rf "$WORK"
    write_status failed "$why; then could not put back: $REASON (the stock copies stay in $BACKUP)"
    log "FAIL: could not put every stock file back: $REASON - do not reboot before checking $LOG"
    report postinstall-rollback-failed "$why / $REASON"
    exit 1
}

SET=$(pick_set) || { SET=; lock "no patch set for $(getprop ro.build.product): its stock files match none of the sets"; }
load_targets || lock "patch set $SET has no targets"
echo "$SET" > "$SET_FILE"
log "patch set $SET ($(car_name "$SET"))"
# 0.1.1: another model than ours: once, which set it took (the server sees nothing else of the add-on)
case "$(getprop ro.build.product)" in NEEV.KOR.*) ;; *) report other-model-set "set $SET; product $(getprop ro.build.product)" ;; esac
[ -f "$R/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml" ] ||
    log "note: the wireless CarPlay feature is not on yet (JMK Wireless AutoPlay does that); turn-by-turn works without it"

# 1. the gate: every target, before anything is written
todo=
for t in $TARGETS; do
    split_target "$t"
    check_target || lock "$REASON"
    if [ "$T_HOW" = build ]; then todo="$todo $t"; else log "$(t_main) ($T_PART) is patched already"; fi
done
check_recipes
if [ -z "$todo" ] && [ -z "$R_TODO" ]; then
    if [ "$prev" = active ]; then st=active; else st=reboot; [ -f "$BOOT_FILE" ] || boot_token > "$BOOT_FILE"; fi
    write_status $st ""
    log "every target is in place already ($st), nothing changed"
    exit 0
fi

# 2. rebuilt from the stock files (a recipe that does not build is skipped, as one that does not fit)
rm -rf "$WORK"
for t in $todo; do
    split_target "$t"
    build_target || fail "$REASON (nothing changed)"
done
r_ok=
for id in $R_TODO; do
    if build_recipe "$id"; then r_ok="$r_ok $id"; else log "WARNING: recipe $id fitted but did not build: skipped"; WARN="${WARN:+$WARN; }recipe $id did not build"; fi
done
R_TODO=$r_ok

# 3. stock copies, then /system
for t in $todo; do
    split_target "$t"
    for f in $(t_files); do backup_file "$f" || fail "$REASON (nothing changed)"; done
done
for id in $R_TODO; do
    f=$(recipe_file "$id")
    backup_file "$f" "$(md5of "$LIB_DIR/$f")" || fail "$REASON (nothing changed)"
done
system_writable || fail "/system is read-only and NEMESIS could not make it writable (nothing changed)"
apps_hold
for t in $todo; do
    split_target "$t"
    apply_target || rollback "$REASON"
done
for id in $R_TODO; do
    apply_recipe "$id" || rollback "$REASON"
done
wipe_dalvik "$(app_names)"
for n in $(app_names); do prefill_dalvik "$n"; done
apps_release
rm -rf "$WORK"
sync
boot_token > "$BOOT_FILE"
write_status reboot ""
log "patched: $(patched_list) ($SET) - reboot the head unit to start them"
exit 0
