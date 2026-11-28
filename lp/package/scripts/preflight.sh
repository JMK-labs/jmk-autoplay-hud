#!/system/bin/sh
# jmk-autoplay-hud (AGPL-3.0): the migration's first step (migrate.meta preflight). JMK Wireless AutoPlay must be installed and at least 0.5.0 (the first LivePatch build).
# Decided here, before the restore and the uninstall of a legacy HUD: NEMESIS would refuse the new HUD on the same rule (depends jmk-autoplay@>=0.5.0, exit 22), but only AFTER the old HUD was taken out.
# Reads the installed version from `nemesis pkg-list` (id|name|locked|types|package-version|...), else from the installed package's own NEMESIS.data. Writes nothing.
# Exit 0 = go on; 1 = refused (the last line says why).
FLOOR_MAJ=0; FLOOR_MIN=5; FLOOR_PAT=0
R=${JMK_HUD_TEST_ROOT:-}
[ -n "$R" ] || export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -z "$JMK_LR_SHIMS" ] || . "$JMK_LR_SHIMS"
NEMESIS_BIN=$R/system/xbin/nemesis
ver=
out=$("$NEMESIS_BIN" pkg-list 2>/dev/null)
while IFS='|' read -r id name locked types pv rest; do
    [ "$id" = jmk-autoplay ] && { ver=$pv; break; }
done <<L
$out
L
if [ -z "$ver" ]; then
    for d in "$R/data/nemesis/apps/jmk-autoplay" "$R/data/nemesis/packages/jmk-autoplay"; do
        [ -r "$d/NEMESIS.data" ] || continue
        while IFS= read -r l || [ -n "$l" ]; do case "$l" in package-version=*) ver=${l#package-version=}; break ;; esac; done < "$d/NEMESIS.data"
        [ -z "$ver" ] || break
    done
fi
if [ -z "$ver" ]; then
    echo "Wireless AutoPlay 0.5 이상이 먼저 필요합니다 (jmk-autoplay is not installed or its version is not readable)"; exit 1
fi
v=$ver; case "$v" in *[!0-9.]*) v=${v%%[!0-9.]*} ;; esac
oldifs=$IFS; IFS=.; set -- $v; IFS=$oldifs
a=${1:-x}; b=${2:-0}; c=${3:-0}
case "$a$b$c" in *[!0-9]*) echo "Wireless AutoPlay 0.5 이상이 먼저 필요합니다 (jmk-autoplay version $ver is not readable)"; exit 1 ;; esac
if [ "$a" -gt $FLOOR_MAJ ] || { [ "$a" -eq $FLOOR_MAJ ] && { [ "$b" -gt $FLOOR_MIN ] || { [ "$b" -eq $FLOOR_MIN ] && [ "$c" -ge $FLOOR_PAT ]; }; }; }; then
    echo "preflight: jmk-autoplay $ver (0.5.0 or newer)"; exit 0
fi
echo "Wireless AutoPlay 0.5 이상이 먼저 필요합니다 (jmk-autoplay $ver is older than 0.5.0)"; exit 1
