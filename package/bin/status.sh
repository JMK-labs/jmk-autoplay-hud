#!/system/bin/sh
# jmk-autoplay-hud: what is in place, for adb (sh /data/nemesis/apps/jmk-autoplay-hud/bin/status.sh). Read only.
# After projection.tbt's bin/status.sh (AGPL-3.0, see LICENSE and NOTICE.md).
PKG=${0%/bin/*}
[ "$PKG" = "$0" ] && PKG=.
. "$PKG/scripts/common.sh"
echo "id=$ID ver=$VER"
echo "product=$(getprop ro.build.product)"
echo "stepofspec=$(getprop ro.product.opt.stepofspec)"
if [ -f "$STATUS" ]; then while IFS= read -r l || [ -n "$l" ]; do echo "status: $l"; done < "$STATUS"; else echo "status: none"; fi
SET=
[ -f "$SET_FILE" ] && read -r SET < "$SET_FILE"
[ -n "$SET" ] || SET=$(pick_set)
echo "set=$SET ($(car_name "$SET"))"
if load_targets; then
    for t in $TARGETS; do
        split_target "$t"
        for f in $(t_files); do
            got=$(md5of "$(live_of "$f")")
            s=$(stock_sum "$f")
            if [ "$f" = "$(t_main)" ] && [ "$got" = "$T_WANT" ]; then w=patched
            elif [ "$got" = "$s" ]; then w=stock
            elif [ -z "$got" ]; then w=missing
            else w=other; fi
            echo "$w $f ${got:-} (stock $s${T_WANT:+, rebuilt $T_WANT})"
        done
    done
fi
if grep navbridge1 "$LIB_DIR/libautoreceiver_infobank.so" >/dev/null 2>&1; then echo "receiver=navbridge"; else echo "receiver=stock"; fi
for p in $LEAFIA_PROPS; do echo "$p=$(getprop "$p")"; done
if [ -f "$CONF" ]; then echo "config: $CONF"; else echo "config: none (defaults)"; fi
[ -d "$BACKUP" ] && echo "backup=$BACKUP" || echo "backup=none"
exit 0
