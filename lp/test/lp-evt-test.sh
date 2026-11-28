#!/usr/bin/env bash
# lp/package scripts/lp-evt.sh and svc/hud.sh's reader: the EVT lines of the patched apps -> one count per day -> one report per counter once the day is over.
# Every case runs under sh and under mksh (the car's shell).
here="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lp-evt.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
SHELLS="sh"; command -v mksh >/dev/null 2>&1 && SHELLS="sh mksh"
cat > "$WORK/shims" <<'SH'
date() { case "$1" in +%s) echo 1795000000 ;; *) cat "$JMK_HUD_TEST_ROOT/date" ;; esac; }
getprop() { case "$1" in sys.boot_completed) echo 1 ;; ro.build.product) echo NEEV.KOR.0000.V039.001.260902 ;; *) : ;; esac; }
setprop() { :; }
sleep() { :; }
SH
car() {   # car <name>: a fresh root with the package copy and an outbox
    T=$WORK/car.$1; P=$T/data/nemesis/apps/jmk-autoplay-hud; rm -rf "$T"
    mkdir -p "$P" "$T/proc/sys/kernel/random" "$T/data/local/tmp/jmk-map-menu/outbox" "$T/data/nemesis/apps/jmk-autoplay" "$T/system/xbin"
    cp -R "$here/../package/." "$P/"
    printf 'id=jmk-autoplay-hud\npackage-version=0.3.2\n' > "$P/NEMESIS.data"
    echo boot-A > "$T/proc/sys/kernel/random/boot_id"
    echo "Sat Nov 28 14:33:12 +09:00 2026" > "$T/date"
    OUT=$T/data/local/tmp/jmk-map-menu/outbox; EV=$T/data/nemesis/jmk-autoplay-hud/evt
}
# run <shell> <commands>: the service libraries sourced in that shell, then the commands
run() {
    local sh=$1; shift
    env JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims PKG=$P "$sh" -c '. "$PKG/scripts/lp-common.sh"; . "$PKG/scripts/lp-status.sh"; . "$PKG/scripts/lp-evt.sh"; '"$*" > "$WORK/out" 2>&1
}
count() { local f=$EV/$1/$2 n=; [ -f "$f" ] && read -r n < "$f"; echo "${n:-none}"; }
for SH in $SHELLS; do
    echo "== $SH"
    car a
    L1='I/JMKHUD  ( 1697): EVT tbt-end why=phone-stop proj=cp seq=1 pid=1697'
    L2='I/JMKHUD  ( 1697): EVT tbt-end why=other proj=cp trig=stock-ns seq=2 pid=1697'
    L3='I/JMKHUD  ( 1697): EVT cp-lanes n=3 app=apple-maps proj=cp seq=3 pid=1697'
    run $SH "evt_line '$L1'; evt_line '$L2'; evt_line '$L3'; evt_line 'I/JMKHUD  ( 1697): Route: ask zero st=0'"
    check "$SH: an end line is counted by why and proj" test "$(count 20261128 end.phone-stop.cp)" = 1
    check "$SH: why=other keeps the hook name" test "$(count 20261128 end.other.cp.stock-ns)" = 1
    check "$SH: a lanes line adds n by app and proj" test "$(count 20261128 lanes.apple-maps.cp)" = 3
    check "$SH: a line that is no EVT line is ignored" test "$(ls "$EV/20261128" | wc -l | tr -d ' ')" = 3
    run $SH "evt_line '$L1'; evt_line '$L2'; evt_line '$L3'"
    check "$SH: the replay of the same lines (a restarted logcat) counts nothing twice" test "$(count 20261128 end.phone-stop.cp)" = 1 -a "$(count 20261128 lanes.apple-maps.cp)" = 3
    run $SH "evt_line 'I/JMKHUD  ( 1697): EVT tbt-end why=phone-stop proj=cp seq=4 pid=1697'; evt_line 'I/JMKHUD  ( 2000): EVT tbt-end why=phone-stop proj=aa seq=1 pid=2000'"
    check "$SH: the next seq of the same process counts, another process counts on its own" test "$(count 20261128 end.phone-stop.cp)" = 2 -a "$(count 20261128 end.phone-stop.aa)" = 1
    run $SH "evt_line 'I/JMKHUD  ( 1697): EVT tbt-end why=Bad_Why proj=cp seq=9 pid=1697'; evt_line 'I/JMKHUD  ( 1697): EVT tbt-end why=other proj=cp trig=a/b seq=10 pid=1697'; evt_line 'I/JMKHUD  ( 1697): EVT tbt-end why=phone-stop proj=cp seq=x pid=1697'"
    check "$SH: a word that is not plain is not counted; a bad hook name becomes unknown; a bad seq is ignored" test "$(ls "$EV/20261128" | tr '\n' ' ')" = "end.other.cp.stock-ns end.other.cp.unknown end.phone-stop.aa end.phone-stop.cp lanes.apple-maps.cp "
    # a new boot: the seen marks go, the same pid and seq count again
    echo boot-B > "$T/proc/sys/kernel/random/boot_id"
    run $SH "evt_boot; evt_line '$L1'"
    check "$SH: a new boot clears the seen marks (a pid comes again)" test "$(count 20261128 end.phone-stop.cp)" = 3
    # the flush: today's counters stay, an earlier day goes out as ONE report per kind, the counters go only after MAP took the file
    run $SH "evt_flush"
    check "$SH: nothing goes out for today" test "$(ls "$OUT" | wc -l | tr -d ' ')" = 0
    echo "Sun Nov 29 00:01:02 +09:00 2026" > "$T/date"
    run $SH "evt_flush"
    check "$SH: the next day: one report per msg (end, lanes), not one per counter" test "$(ls "$OUT" | wc -l | tr -d ' ')" = 2
    f=$OUT/jmk-autoplay-hud-hud-20261128-end.json
    check "$SH: tbt end report: msg, type, period, every key as a line of the detail" bash -c "grep -q '\"msg\":\"hud: tbt end\"' $f && grep -q '\"type\":\"hud\"' $f && grep -q '\"period\":\"20261128\"' $f && grep -q 'day=2026-11-28 ver=0.3.2' $f && grep -qF 'why=phone-stop proj=cp n=3' $f && grep -qF 'why=other proj=cp trig=stock-ns n=1' $f && grep -qF 'why=other proj=cp trig=unknown n=1' $f && grep -qF 'why=phone-stop proj=aa n=1' $f"
    check "$SH: the detail is one JSON string with \\n between the lines (valid JSON)" bash -c "python3 -c \"import json,sys; d=json.load(open('$f')); assert d['detail'].count(chr(10))==4, d['detail']\""
    f=$OUT/jmk-autoplay-hud-hud-20261128-lanes.json
    check "$SH: lanes report: the exact msg, period and the app proj n line" bash -c "grep -q '\"msg\":\"cp lanes: 0x5204 seen\"' $f && grep -q '\"period\":\"20261128\"' $f && grep -qF 'app=apple-maps proj=cp n=3' $f"
    check "$SH: the counters stay until MAP takes the file (marker written, counter kept)" test "$(count 20261128 end.phone-stop.cp)" = 3 -a -f "$EV/20261128/.sent-end" -a -f "$EV/20261128/.sent-lanes"
    run $SH "evt_flush"
    check "$SH: a second flush with the files still there writes nothing new and keeps the counters" test "$(ls "$OUT" | wc -l | tr -d ' ')" = 2 -a "$(count 20261128 end.phone-stop.cp)" = 3
    rm -f "$OUT/jmk-autoplay-hud-hud-20261128-end.json"      # MAP took the tbt-end report
    run $SH "evt_flush"
    check "$SH: the taken kind's counters are gone, the other kind (file still waiting) keeps its own" test "$(count 20261128 end.phone-stop.cp)" = none -a "$(count 20261128 lanes.apple-maps.cp)" = 3
    rm -f "$OUT"/*
    run $SH "evt_flush"
    check "$SH: both taken: the day is gone, nothing is sent twice" test ! -d "$EV/20261128" -a "$(ls "$OUT" | wc -l | tr -d ' ')" = 0
    # no outbox: the counters stay, no marker
    car b; echo "Sat Nov 28 10:00:00 +09:00 2026" > "$T/date"
    run $SH "evt_line '$L1'"; echo "Sun Nov 29 00:01:02 +09:00 2026" > "$T/date"; rmdir "$OUT"
    run $SH "evt_flush"
    check "$SH: without the MAP outbox the counter stays for later, no marker" test "$(count 20261128 end.phone-stop.cp)" = 1 -a ! -f "$EV/20261128/.sent-end"
    mkdir -p "$OUT"; run $SH "evt_flush"
    check "$SH: and goes out when the outbox is there" test -f "$OUT/jmk-autoplay-hud-hud-20261128-end.json"
    # a clock that is not set (before 2026) counts nothing
    car e; echo "Thu Jan  1 00:00:05 +09:00 1970" > "$T/date"; run $SH "evt_line '$L1'"
    check "$SH: a clock before 2026 (not set yet) counts nothing" test "$(ls "$EV" 2>/dev/null | grep -c '^1970')" = 0 -a ! -d "$EV/19700101"
    # year end and the date that cannot be read
    car c; echo "Thu Dec 31 23:59:59 +09:00 2026" > "$T/date"; run $SH "evt_line '$L1'"
    check "$SH: Dec 31 is its own day" test "$(count 20261231 end.phone-stop.cp)" = 1
    echo "garbage" > "$T/date"; run $SH "evt_line 'I/JMKHUD  ( 1697): EVT tbt-end why=phone-stop proj=cp seq=77 pid=1697'"
    check "$SH: a date that cannot be read counts nothing and does not fail" test "$(count 20261231 end.phone-stop.cp)" = 1
    # the reader through the service (one pass, the command replaced): lines in, counters out
    car d; echo "Sat Nov 28 14:33:12 +09:00 2026" > "$T/date"
    printf 'I/JMKHUD  ( 1697): EVT tbt-end why=session-end proj=cp seq=1 pid=1697\nI/JMKHUD  ( 1697): EVT tbt-end why=session-end proj=cp seq=2 pid=1697\n' > "$T/lines"
    mkdir -p "$T/data/nemesis/jmk-autoplay-hud"; : > "$T/data/nemesis/jmk-autoplay-hud/installed"
    printf '#!/bin/sh\n[ "$1 $2" = "livepatch status" ] && printf "wrapper=1 safe=0\\n/system/app/HKMC_DiPO.odex mounted\\n"\nexit 0\n' > "$T/system/xbin/nemesis"; chmod +x "$T/system/xbin/nemesis"
    printf '#!/bin/sh\n[ "$1" = profile ] || exit 1\necho "profile=kr parts=2_tbt 3_bridge apps=HKMC_DiPO libs="\n' > "$P/tools/hud-step"; chmod +x "$P/tools/hud-step"
    mkdir -p "$P/tools/patches/bycode/kr"; echo "log lane_dist cp_lanes cp_keepbt" > "$P/tools/patches/bycode/kr/knobs"
    env JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims JMK_HUD_PKG=$P JMK_HUD_ONCE=1 JMK_HUD_EVT_CMD="cat $T/lines" "$SH" "$P/svc/hud.sh" > "$WORK/out" 2>&1
    check "$SH: the service reads the reader's lines (ONCE with a command) and counts them" test "$(count 20261128 end.session-end.cp)" = 2
    check "$SH: the service wrote the pid file of the reader" test -f "$T/data/nemesis/jmk-autoplay-hud/evt.pid"
    # the raw lane messages (the decoder's own counting lines) go into the daily "cp lanes: 0x5204 seen" report as one summary line; with no cp-lanes line at all they still make the report
    car w; echo "Sat Nov 28 14:33:12 +09:00 2026" > "$T/date"
    R1='I/JMKHUD  ( 1697): EVT cp-raw res=ok layout=a why=- seq='
    R2='I/JMKHUD  ( 1697): EVT cp-raw res=bad layout=- why=tlv seq='
    run $SH "evt_line '${R1}1 pid=1697'; evt_line '${R1}2 pid=1697'; evt_line '${R1}3 pid=1697'; evt_line 'I/JMKHUD  ( 1697): EVT cp-raw res=ok layout=b why=- seq=4 pid=1697'; evt_line '${R2}5 pid=1697'; evt_line '${R2}6 pid=1697'; evt_line 'I/JMKHUD  ( 1697): EVT cp-raw res=bad layout=ab why=short seq=7 pid=1697'; evt_line '${R1}3 pid=1697'"
    check "$SH: raw lines are counted by result, layout and reason (a replayed seq counts once)" test "$(count 20261128 raw.ok.a)" = 3 -a "$(count 20261128 raw.ok.b)" = 1 -a "$(count 20261128 raw.bad.tlv)" = 2 -a "$(count 20261128 raw.bad.short)" = 1 -a "$(count 20261128 raw.bad.ab)" = none
    echo "Sun Nov 29 00:01:02 +09:00 2026" > "$T/date"; run $SH "evt_flush"
    f=$OUT/jmk-autoplay-hud-hud-20261128-lanes.json
    check "$SH: the lanes report exists with only raw counts, the exact msg, and the summary keys" bash -c "[ -f $f ] && grep -q '\"msg\":\"cp lanes: 0x5204 seen\"' $f && grep -qF 'raw_ok=4 raw_bad=3 bad_why=tlv layout=a' $f"
    check "$SH: no tbt-end report was made from raw lines" test ! -f "$OUT/jmk-autoplay-hud-hud-20261128-end.json"
    rm -f "$OUT/jmk-autoplay-hud-hud-20261128-lanes.json"; run $SH "evt_flush"
    check "$SH: once MAP took the file the raw counters go with the lanes counters" test ! -d "$EV/20261128"
    car v; echo "Sat Nov 28 14:33:12 +09:00 2026" > "$T/date"
    run $SH "evt_line 'I/JMKHUD  ( 1697): EVT cp-lanes n=2 app=apple-maps proj=cp seq=1 pid=1697'; evt_line '${R1}2 pid=1697'"
    echo "Sun Nov 29 00:01:02 +09:00 2026" > "$T/date"; run $SH "evt_flush"
    f=$OUT/jmk-autoplay-hud-hud-20261128-lanes.json
    check "$SH: with a cp-lanes line the report holds the app line and the raw summary" bash -c "grep -qF 'app=apple-maps proj=cp n=2' $f && grep -qF 'raw_ok=1 raw_bad=0 bad_why=- layout=a' $f && grep -q 'period' $f"
    # the reader: stop leaves no child, no counting; a second start never starts a second reader
    car r; echo "Sat Nov 28 14:33:12 +09:00 2026" > "$T/date"; : > "$T/fakelog"; cat > "$T/fakelog" <<'F'
#!/bin/sh
i=1
while true; do echo "I/JMKHUD  ( 1697): EVT tbt-end why=phone-stop proj=cp seq=$i pid=1697"; i=$((i + 1)); /bin/sleep 1; done
F
    mkdir -p "$T/data/nemesis/jmk-autoplay-hud"
    env JMK_HUD_TEST_ROOT=$T PKG=$P JMK_HUD_EVT_CMD="sh $T/fakelog" "$SH" -c '. "$PKG/scripts/lp-common.sh"; . "$PKG/scripts/lp-status.sh"; . "$PKG/scripts/lp-evt.sh"
        evt_reader_start; evt_reader_start; /bin/sleep 2
        read -r a < "$EVT_PID"; read -r b < "$EVT_LPID"; echo "pids $a $b"
        evt_reader_stop; /bin/sleep 3; echo "alive-after-stop $(kill -0 $a 2>/dev/null && echo a)$(kill -0 $b 2>/dev/null && echo b)"' > "$WORK/out" 2>&1
    EVD=$T/data/nemesis/jmk-autoplay-hud/evt
    c1=$(count 20261128 end.phone-stop.cp); /bin/sleep 3; c2=$(count 20261128 end.phone-stop.cp)
    check "$SH: the reader counted while it ran" test "$c1" != none
    check "$SH: after stop neither the loop nor logcat's stand-in is alive" grep -q "^alive-after-stop $" "$WORK/out"
    check "$SH: and nothing is counted after the stop" test "$c1" = "$c2"
    check "$SH: no second reader came from the second start (one fake process)" test "$(grep -c '^pids ' "$WORK/out")" = 1 -a "$(ps -ax -o command | grep -c "[s]h $T/fakelog")" = 0
done
echo "---- $PASS passed, $FAILN failed"
[ $FAILN -eq 0 ]
