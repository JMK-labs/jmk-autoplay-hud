#!/system/bin/sh
# jmk-autoplay-hud (AGPL-3.0): does this firmware still need the converter (libev6aac.so) for Wi-Fi CarPlay audio?
# Read from the live libCarPlayUtils.so by the recipe's own check (lpatch check), never from a model name or a chip guess:
#   PATCHABLE (the stock bytes that the converter recipe patches) or APPLIED (patched already)  -> needed
#   NATIVE (the firmware converts by itself), MISMATCH / MISSING (this firmware does not take the recipe)  -> native
# A converter file we added (libev6aac.so recorded as added by the legacy HUD, still there) is also "needed".
# Prints one line:  converter=needed|native|unknown state=<PATCHABLE|APPLIED|NATIVE|MISMATCH|MISSING|ERROR> [added=1]
# Exit: 0 native, 11 needed (the LivePatch HUD does not ship the converter: this car stays on the legacy HUD until a
#       firmware update makes the state NATIVE), 70 could not tell (lpatch did not run): treated as a refusal by the callers.
# Run from the unpacked zip (migrate/pre-install gate) or from the installed package; writes nothing.
here=${0%/*}
case "$here" in /*) ;; *) here=$(pwd)/$here ;; esac
PKG=$here/..                                  # found from $0 (the runner's JMK_PKG is the package id, not a folder)
R=${JMK_HUD_TEST_ROOT:-}
[ -n "$R" ] || export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -z "$JMK_LR_SHIMS" ] || . "$JMK_LR_SHIMS"
LPATCH=${JMK_LPATCH:-$PKG/tools/lpatch}
RECIPE=$PKG/files/carplay-utils-converter.recipe
LIB=$R/system/lib/libCarPlayUtils.so
ADDED=$R/data/nemesis/jmk-autoplay-hud/added
state=ERROR
if [ ! -f "$LIB" ]; then
    state=MISSING
elif [ -f "$RECIPE" ]; then
    chmod 0755 "$LPATCH" 2>/dev/null
    out=$("$LPATCH" check "$RECIPE" "$LIB" 2>&1)
    set -f
    for w in $out; do case "$w" in status=*) state=${w#status=} ;; esac; done
    set +f
fi
added=
if [ -f "$ADDED" ] && [ -e "$R/system/lib/libev6aac.so" ]; then
    while read -r f s _ || [ -n "$f" ]; do [ "$f" = libev6aac.so ] && added=" added=1"; done < "$ADDED"
fi
case "$state" in
    PATCHABLE|APPLIED) echo "converter=needed state=$state$added"; exit 11 ;;
    NATIVE|MISMATCH|MISSING)
        if [ -n "$added" ]; then echo "converter=needed state=$state$added"; exit 11; fi
        echo "converter=native state=$state"; exit 0 ;;
    *) echo "converter=unknown state=$state$added"; exit 70 ;;
esac
