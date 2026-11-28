# jmk-autoplay-hud (LivePatch build) shared shell (AGPL-3.0, see LICENSE and NOTICE.md). Sourced by preinstall/postinstall.
ID=jmk-autoplay-hud
R=${JMK_HUD_TEST_ROOT:-}                  # a sandbox root for the Mac tests only; empty on the car
PKG=${PKG:-.}
STORE=$R/data/nemesis/$ID
LOG=$R/data/nemesis/$ID.log
REPORTED=$R/data/nemesis/$ID.reported
NEMESIS_BIN=$R/system/xbin/nemesis
[ -n "$R" ] || export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -z "$JMK_LR_SHIMS" ] || . "$JMK_LR_SHIMS"   # tests only

log() { echo "$1"; mkdir -p "${LOG%/*}" 2>/dev/null; echo "$(date) $1" >> "$LOG" 2>/dev/null; true; }
pkg_version() {
    local l
    [ -r "$PKG/NEMESIS.data" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in package-version=*) echo "${l#package-version=}"; return 0 ;; esac; done < "$PKG/NEMESIS.data"
    return 1
}
VER=$(pkg_version) || VER=unknown
has_line() {
    local l
    [ -f "$2" ] || return 1
    while IFS= read -r l || [ -n "$l" ]; do [ "$l" = "$1" ] && return 0; done < "$2"
    return 1
}
# One install report per version and category, through the JMK MAP menu's outbox (it sends them when online).
report() {
    local box=$R/data/local/tmp/jmk-map-menu/outbox detail=$2 tmp
    [ -d "$box" ] || return 0
    case "$1" in ''|*[!a-z0-9-]*) return 0 ;; esac
    case "$VER" in ''|*[!0-9.]*) return 0 ;; esac
    has_line "$VER $1" "$REPORTED" && return 0
    case "$detail" in *'"'*|*'\'*) detail='(detail not printable)' ;; esac
    tmp=$box/.$ID-install-$$.tmp
    echo "{\"kind\":\"jmk-report\",\"type\":\"install\",\"app\":\"$ID\",\"ver\":\"$VER\",\"msg\":\"install: $1\",\"detail\":\"$detail\",\"at\":$(date +%s)000}" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    chmod 0644 "$tmp"
    mv "$tmp" "$box/$ID-install-$1.json" && echo "$VER $1" >> "$REPORTED"
    return 0
}
pkg_installed() { [ -d "$R/data/nemesis/apps/$1" ] || [ -d "$R/data/nemesis/packages/$1" ]; }
other_projection() {
    local d id
    for d in "$R"/data/nemesis/apps/* "$R"/data/nemesis/packages/*; do
        [ -d "$d" ] || continue
        id=${d##*/}
        case "$id" in
            jmk-*|jmk.*) ;;
            wireless.*|*projection*|*carplay*|*androidauto*|*leafia*|*evergreen*|danpung*|aa.usbwifi|*.tbt|*.tbt.*)
                echo "$id"; return 0 ;;
        esac
    done
    for d in "$R"/data/hmgapi/mods/*; do
        [ -d "$d" ] || continue
        case "${d##*/}" in *wireless*|*carplay*|*projection*|*tbt*) echo "HMG-API mod ${d##*/}"; return 0 ;; esac
    done
    return 1
}
