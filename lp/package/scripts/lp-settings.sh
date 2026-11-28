# jmk-autoplay-hud (LivePatch build): the settings bridge, from the JMK MAP menu's config to the persist.leafia.* switches the patched apps read (AGPL-3.0, see LICENSE and NOTICE.md).
# Sourced after lp-common.sh. The profile's knobs file (tools/patches/bycode/<profile>/knobs) says which keys its builds really read; a key without a switch is ignored.
CONF=$R/data/local/tmp/$ID/config      # written by the menu's daemon (key=value)
knob_props() {
    case "$1" in
        log) echo "persist.leafia.log persist.leafia.lane.log" ;;   # Leafia writes both for its "log" key
        lane_dist) echo persist.leafia.lane.dist ;;
        cp_lanes) echo persist.leafia.cp.lanes ;;                   # the bridge Iap2ServerApp: ask CarPlay for lanes
        cp_keepbt) echo persist.leafia.cp.keepbt ;;                 # the bridge HKMC_DiPO: wireless CarPlay keeps the phone's Bluetooth
        *) return 1 ;;
    esac
}
knob_value() {   # knob_value <key> <config value>: the switch value; anything but a valid value gives the default
    case "$1" in
        log) case "$2" in 0) echo 0 ;; *) echo 1 ;; esac ;;
        lane_dist) case "$2" in 0) echo off ;; *) echo label ;; esac ;;
        cp_lanes) case "$2" in 0) echo 0 ;; *) echo 1 ;; esac ;;
        cp_keepbt) case "$2" in 0) echo 0 ;; *) echo 1 ;; esac ;;
        *) return 1 ;;
    esac
}
LEAFIA_OTHER_PROPS="persist.leafia.lane.src persist.leafia.lane.hl persist.leafia.lane.mode persist.leafia.lane.gauge persist.leafia.lane.dim persist.leafia.lane.gate persist.leafia.turn.split persist.leafia.tbt.standard persist.leafia.owner.r4bridge persist.leafia.delete.aa"
LEAFIA_PROPS="persist.leafia.log persist.leafia.lane.log persist.leafia.lane.dist persist.leafia.cp.lanes persist.leafia.cp.keepbt $LEAFIA_OTHER_PROPS"
conf_get() {
    local l
    [ -f "$CONF" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$1="*) echo "${l#*=}"; return 0 ;; esac; done < "$CONF"
    return 1
}
# knob_keys <profile>: the keys of that profile's knobs file (words per line, '#' lines skipped)
knob_keys() {
    local f=$PKG/tools/patches/bycode/$1/knobs l
    [ -n "$1" ] && [ -f "$f" ] || return 0
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in ''|'#'*) continue ;; esac; echo $l; done < "$f"
}
CONF_SIG=
apply_config() {   # apply_config <profile> [force]: when the config changed (or force), each knob's switch set to its value (only when it differs)
    local sig= l k want p changed=
    if [ -f "$CONF" ]; then while IFS= read -r l || [ -n "$l" ]; do sig="$sig|$l"; done < "$CONF"; else sig=none; fi
    [ "$2" = force ] || [ "$sig" != "$CONF_SIG" ] || return 0
    CONF_SIG=$sig
    for k in $(knob_keys "$1"); do
        want=$(knob_value "$k" "$(conf_get "$k")") || continue
        for p in $(knob_props "$k"); do
            [ "$(getprop "$p")" = "$want" ] && continue
            setprop "$p" "$want" && changed="$changed $p=$want"
        done
    done
    for p in $LEAFIA_OTHER_PROPS; do
        [ -n "$(getprop "$p")" ] || continue
        setprop "$p" "" && changed="$changed $p=(cleared)"
    done
    [ -n "$changed" ] && log "settings:$changed"
    return 0
}
leafia_props_clear() {   # a real uninstall leaves no switch behind
    local p
    for p in $LEAFIA_PROPS; do [ -n "$(getprop "$p")" ] && setprop "$p" ""; done
    return 0
}
