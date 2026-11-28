# jmk-autoplay-hud (LivePatch build): the counts of the patched apps' EVT lines (AGPL-3.0, see LICENSE and NOTICE.md). Sourced after lp-common.sh and lp-status.sh.
# The apps write one plain line per event to the log tag JMKHUD:
#   EVT tbt-end why=<phone-stop|session-end|source-change|restart|other> proj=<cp|aa> [trig=<hook>] seq=<n> pid=<p>
#   EVT cp-lanes n=<count> app=<token> proj=<cp|aa> seq=<n> pid=<p>
#   EVT cp-raw res=<ok|bad> layout=<a|b|ab|-> why=<code|-> seq=<n> pid=<p>      (the raw lane messages the decoder read or refused; counted into the lanes report)
# This service reads them with ONE streaming logcat child (restarted only when it exits), adds them up per day in $EVT_DIR/<YYYYMMDD>/<key>, and sends
# each finished day's counts once through the MAP menu's outbox: ONE report per msg per day, all keys in its detail, "period":"<YYYYMMDD>" (MAP >= 2.4.2 counts the
# once-a-day rule per period): msg "hud: tbt end" (lines "why= proj= [trig=] n=") and "cp lanes: 0x5204 seen" (lines "app= proj= n="). A counter is removed
# only after MAP has taken its report file out of the outbox (sent, or dropped as a duplicate).
# A line is counted once: seen[boot-pid] holds the last seq of that process (a restarted logcat replays the buffer). Nothing here writes /system.
EVT_DIR=$STORE/evt
EVT_SEEN=$EVT_DIR/seen
EVT_PID=$STORE/evt.pid                 # the reader's outer subshell
EVT_LPID=$STORE/evt.logcat.pid         # the logcat child itself
evt_plain() { case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac; [ ${#1} -le 24 ]; }
# evt_day: YYYYMMDD from `date` ("Sat Nov 28 14:33:12 KST 2026"); nothing when it cannot be read
evt_day() {
    local d m dd y mm
    set -- $(date)
    [ $# -ge 6 ] || return 1
    m=$2; dd=$3; eval "y=\${$#}"
    case "$m" in Jan) mm=01 ;; Feb) mm=02 ;; Mar) mm=03 ;; Apr) mm=04 ;; May) mm=05 ;; Jun) mm=06 ;; Jul) mm=07 ;; Aug) mm=08 ;; Sep) mm=09 ;; Oct) mm=10 ;; Nov) mm=11 ;; Dec) mm=12 ;; *) return 1 ;; esac
    case "$dd" in ?) dd=0$dd ;; esac
    case "$y$dd" in *[!0-9]*) return 1 ;; esac
    [ "$y" -ge 2026 ] || return 1      # MAP's CLOCK_OK (2026-01-01): an earlier clock is not set yet, nothing is counted
    echo "$y$mm$dd"
}
# evt_add <key> <n>: adds n to today's counter of key
evt_add() {
    local day cur=0 f
    day=$(evt_day) || return 0
    mkdir -p "$EVT_DIR/$day" 2>/dev/null || return 0
    f=$EVT_DIR/$day/$1
    [ -f "$f" ] && read -r cur < "$f"
    case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
    echo $((cur + $2)) > "$f"
}
# evt_line <one logcat line>: counts it when it is an EVT line not seen before
evt_line() {
    local kind rest w why= proj= trig= n=1 app= seq= pid= last=0 f key res= lay=
    case "$1" in
        *"EVT tbt-end "*) kind=end; rest=${1#*EVT tbt-end } ;;
        *"EVT cp-lanes "*) kind=lanes; rest=${1#*EVT cp-lanes } ;;
        *"EVT cp-raw "*) kind=raw; rest=${1#*EVT cp-raw } ;;
        *) return 0 ;;
    esac
    for w in $rest; do
        case "$w" in why=*) why=${w#why=} ;; proj=*) proj=${w#proj=} ;; trig=*) trig=${w#trig=} ;; n=*) n=${w#n=} ;; app=*) app=${w#app=} ;; seq=*) seq=${w#seq=} ;; pid=*) pid=${w#pid=} ;; res=*) res=${w#res=} ;; layout=*) lay=${w#layout=} ;; esac
    done
    case "$seq" in ''|*[!0-9]*) return 0 ;; esac
    case "$pid" in ''|*[!0-9]*) return 0 ;; esac
    case "$n" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$kind" != raw ]; then evt_plain "$proj" || return 0; fi
    mkdir -p "$EVT_SEEN" 2>/dev/null
    f=$EVT_SEEN/$(boot_token)-$pid
    [ -f "$f" ] && read -r last < "$f"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    [ "$seq" -gt "$last" ] || return 0
    echo "$seq" > "$f"
    if [ "$kind" = raw ]; then
        evt_plain "$lay" || lay=-
        case "$res" in
            ok) evt_add "raw.ok.$lay" 1 ;;
            bad) evt_plain "$why" || why=-; evt_add "raw.bad.${why:--}" 1 ;;
        esac
        return 0
    fi
    if [ "$kind" = end ]; then
        evt_plain "$why" || return 0
        key=end.$why.$proj
        if [ "$why" = other ]; then evt_plain "${trig:-unknown}" || trig=unknown; key=$key.${trig:-unknown}; fi
        evt_add "$key" 1
    else
        evt_plain "$app" || app=unknown
        evt_add "lanes.$app.$proj" "$n"
    fi
}
# the day's counters of one kind -> the lines of one report: evt_lines <day dir> <end|lanes>
evt_lines() {
    local f k rest n why proj trig app
    for f in "$1"/$2.*; do
        [ -f "$f" ] || continue
        n=; read -r n < "$f"
        case "$n" in ''|*[!0-9]*) continue ;; esac
        k=${f##*/}; rest=${k#*.}
        if [ "$2" = end ]; then
            why=${rest%%.*}; rest=${rest#*.}; proj=${rest%%.*}; trig=; case "$rest" in *.*) trig=${rest#*.} ;; esac
            echo "why=$why proj=$proj${trig:+ trig=$trig} n=$n"
        else
            app=${rest%%.*}; proj=${rest#*.}
            echo "app=$app proj=$proj n=$n"
        fi
    done
}
# the raw lane messages of the day as one line: raw_ok=<n> raw_bad=<n> bad_why=<the most frequent reason|-> layout=<the layout that matched most|->
evt_raw_summary() {
    local f k n ok=0 bad=0 bw=- bn=0 lay=- ln=0
    for f in "$1"/raw.ok.*; do
        [ -f "$f" ] || continue
        n=; read -r n < "$f"; case "$n" in ''|*[!0-9]*) continue ;; esac
        ok=$((ok + n)); k=${f##*/}; k=${k#raw.ok.}
        [ $n -gt $ln ] && { ln=$n; lay=$k; }
    done
    for f in "$1"/raw.bad.*; do
        [ -f "$f" ] || continue
        n=; read -r n < "$f"; case "$n" in ''|*[!0-9]*) continue ;; esac
        bad=$((bad + n)); k=${f##*/}; k=${k#raw.bad.}
        [ $n -gt $bn ] && { bn=$n; bw=$k; }
    done
    [ $((ok + bad)) -gt 0 ] && echo "raw_ok=$ok raw_bad=$bad bad_why=$bw layout=$lay"
}
# evt_send <day YYYYMMDD> <end|lanes> <lines>: the one report file of that kind and day; false when the outbox is not there
evt_send() {
    local box=$R/data/local/tmp/jmk-map-menu/outbox day=$1 kind=$2 lines=$3 d y mm dd msg tmp name l body=
    [ -d "$box" ] || return 1
    case "$VER" in ''|*[!0-9.]*) return 1 ;; esac
    y=${day%????}; mm=${day#????}; dd=${mm#??}; mm=${mm%??}; d=$y-$mm-$dd
    case "$kind" in end) msg="hud: tbt end" ;; lanes) msg="cp lanes: 0x5204 seen" ;; *) return 1 ;; esac
    while IFS= read -r l; do [ -n "$l" ] && body="$body\\n$l"; done <<EOT
$lines
EOT
    name=$box/$ID-hud-$day-$kind.json
    tmp=$box/.$ID-hud-$$.tmp
    cat > "$tmp" 2>/dev/null <<EOT || { rm -f "$tmp"; return 1; }
{"kind":"jmk-report","type":"hud","app":"$ID","ver":"$VER","msg":"$msg","detail":"day=$d ver=$VER$body","period":"$day","at":$(date +%s)000}
EOT
    chmod 0644 "$tmp"
    mv "$tmp" "$name"
}
# evt_flush: every day before today. Per kind: no marker -> write the report and the marker; marker and the file still in the outbox -> MAP has not taken it, wait;
# marker and the file gone -> MAP took it (sent, or dropped as a duplicate): the counters of that kind go
evt_flush() {
    local today dd day kind f l lines box=$R/data/local/tmp/jmk-map-menu/outbox
    today=$(evt_day) || return 0
    [ -d "$EVT_DIR" ] || return 0
    [ -d "$box" ] || return 0
    for dd in "$EVT_DIR"/*; do
        [ -d "$dd" ] || continue
        day=${dd##*/}
        case "$day" in ''|*[!0-9]*|seen) continue ;; esac
        [ "$day" -lt "$today" ] || continue
        for kind in end lanes; do
            if [ -f "$dd/.sent-$kind" ]; then
                [ -f "$box/$ID-hud-$day-$kind.json" ] && continue
                for f in "$dd"/$kind.*; do [ -f "$f" ] && rm -f "$f"; done
                [ $kind != lanes ] || for f in "$dd"/raw.*; do [ -f "$f" ] && rm -f "$f"; done
                rm -f "$dd/.sent-$kind"
                continue
            fi
            lines=$(evt_lines "$dd" $kind)
            if [ $kind = lanes ]; then l=$(evt_raw_summary "$dd"); [ -z "$l" ] || lines="${lines:+$lines
}$l"; fi
            [ -n "$lines" ] || continue
            if evt_send "$day" $kind "$lines"; then : > "$dd/.sent-$kind"; fi
        done
        for f in "$dd"/* "$dd"/.sent-*; do [ -f "$f" ] && continue 2; done
        rmdir "$dd" 2>/dev/null
    done
}
# the reader: ONE logcat child behind a read loop; JMK_HUD_EVT_CMD replaces the command in the tests. Both pids are kept: the outer subshell and logcat itself.
evt_pid_alive() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; kill -0 "$1" 2>/dev/null; }
evt_reader_alive() {
    local pid
    [ -f "$EVT_PID" ] || return 1
    read -r pid < "$EVT_PID" || return 1
    evt_pid_alive "$pid" || return 1
    [ -n "$R" ] || grep -q 'svc/hud.sh' "/proc/$pid/cmdline" 2>/dev/null   # on the car: that pid is still our service's subshell (a pid of an earlier boot may belong to anything)
}
evt_reader_start() {
    evt_reader_alive && return 0          # never a second reader (an update that did not stop the old one, a double start)
    rm -f "$EVT_LPID"
    ( ( ${JMK_HUD_EVT_CMD:-logcat -v brief -s JMKHUD:I} 2>/dev/null & echo $! > "$EVT_LPID"; wait ) | while IFS= read -r l || [ -n "$l" ]; do evt_line "$l"; done ) &
    echo $! > "$EVT_PID"
}
# stop: logcat itself first (the read loop then ends on EOF), then the outer subshell; on the car a pid is only killed when its command line is ours
evt_kill_pid() {   # evt_kill_pid <pidfile> <word the command line must hold>
    local pid
    [ -f "$1" ] || return 0
    read -r pid < "$1"
    if evt_pid_alive "$pid"; then
        if [ -n "$R" ] || grep -q "$2" "/proc/$pid/cmdline" 2>/dev/null; then kill "$pid" 2>/dev/null; fi
    fi
    rm -f "$1"
}
evt_reader_stop() {
    local w=${JMK_HUD_EVT_CMD:-logcat}
    w=${w%% *}; w=${w##*/}
    evt_kill_pid "$EVT_LPID" "$w"
    evt_kill_pid "$EVT_PID" 'svc/hud.sh'
}
# at a new boot the seen marks of the old one go (a pid may come again)
evt_boot() {
    local b f
    mkdir -p "$EVT_SEEN" 2>/dev/null
    b=$(boot_token)
    [ -f "$EVT_DIR/boot" ] && read -r f < "$EVT_DIR/boot"
    [ "$f" = "$b" ] && return 0
    for f in "$EVT_SEEN"/*; do [ -f "$f" ] && rm -f "$f"; done
    echo "$b" > "$EVT_DIR/boot"
}
