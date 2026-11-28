#!/usr/bin/env bash
# lp/package/scripts/converter-check.sh + preinstall.sh in a fake car root.
here="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jmk-lp-gates.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
PK=$WORK/pkg; cp -R "$here/../package" "$PK"; printf 'id=jmk-autoplay-hud\npackage-version=0.3.0\n' > "$PK/NEMESIS.data"   # a fixture version (the generator writes the real file)
PASS=0; FAILN=0
ok() { echo "ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1${2:+: $2}"; FAILN=$((FAILN + 1)); }
check() { local n=$1; shift; if "$@"; then ok "$n"; else fail "$n"; fi; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
cat > "$WORK/shims" <<'SH'
md5() { command md5 -r "$1" 2>/dev/null; }
getprop() { echo; }
SH
printf '#!/bin/sh\n[ "$1" = check ] && [ -n "$LPSTATE" ] && echo "status=$LPSTATE"; [ "$LPSTATE" = FAIL ] && exit 1; exit 0\n' > "$WORK/lpatch"; chmod +x "$WORK/lpatch"
car() {   # car <name> <lpatch state> [nemesis version] [livepatch status]
    T=$WORK/car.$1; rm -rf "$T"; mkdir -p "$T/system/lib" "$T/system/xbin" "$T/data/nemesis/apps/jmk-autoplay" "$T/data/local/tmp/jmk-map-menu/outbox"
    echo lib > "$T/system/lib/libCarPlayUtils.so"
    export LPSTATE=$2 NV=${3:-1.17.0} LPS=${4:-"wrapper=1 safe=0"}
    cat > "$T/system/xbin/nemesis" <<'N'
#!/bin/sh
case "$1" in version) echo "NEMESIS $NV" ;; livepatch) echo "$LPS" ;; esac
N
    chmod +x "$T/system/xbin/nemesis"
}
export JMK_LPATCH=$WORK/lpatch
cc() { OUT=$(JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims sh "$PK/scripts/converter-check.sh" 2>&1); RC=$?; }
pre() { OUT=$(cd "$PK" && PKG="$PK" JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims sh ./scripts/preinstall.sh 2>&1); RC=$?; }

car a PATCHABLE; cc; check "PATCHABLE -> needed, exit 11" test $RC = 11; check "  line" has "converter=needed state=PATCHABLE"
car b APPLIED;   cc; check "APPLIED -> needed, exit 11" test $RC = 11
car c NATIVE;    cc; check "NATIVE -> native, exit 0" test $RC = 0; check "  line" has "converter=native state=NATIVE"
car d MISMATCH;  cc; check "MISMATCH -> native, exit 0" test $RC = 0
car e NATIVE; rm "$T/system/lib/libCarPlayUtils.so"; cc; check "no library -> native (MISSING), exit 0" test $RC = 0; check "  line" has "state=MISSING"
car f FAIL; cc; check "lpatch fails -> unknown, exit 70" test $RC = 70; check "  line" has "converter=unknown"
car g NATIVE; mkdir -p "$T/data/nemesis/jmk-autoplay-hud"; echo "libev6aac.so abc" > "$T/data/nemesis/jmk-autoplay-hud/added"; echo x > "$T/system/lib/libev6aac.so"
cc; check "our converter file still there -> needed, exit 11" test $RC = 11; check "  line" has "added=1"

car h NATIVE; pre; check "preinstall: native car passes" test $RC = 0
car i PATCHABLE; pre; check "preinstall: converter car refused (1)" test $RC = 1
check "  reason" has "converter"
check "  report written: install: needs-converter" test -f "$T/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-needs-converter.json"
car j FAIL; pre; check "preinstall: cannot tell -> refused" test $RC = 1
check "  report converter-check-failed" test -f "$T/data/local/tmp/jmk-map-menu/outbox/jmk-autoplay-hud-install-converter-check-failed.json"
car k NATIVE 1.16.2; pre; check "preinstall: NEMESIS 1.16.2 refused" test $RC = 1
car l NATIVE 1.17.0 "wrapper=0 safe=0"; pre; check "preinstall: wrapper off refused" test $RC = 1
car m NATIVE 1.17.1 "wrapper=1 safe=1"; pre; check "preinstall: safe mode refused" test $RC = 1
car n NATIVE 1.18.0 ""; pre; check "preinstall: 1.18, status unreadable: passes" test $RC = 0
car o NATIVE; rmdir "$T/data/nemesis/apps/jmk-autoplay"; pre; check "preinstall: no AutoPlay refused" test $RC = 1
car p NATIVE; mkdir "$T/data/nemesis/apps/danpung"; pre; check "preinstall: danpung refused" test $RC = 1
car q NATIVE; mkdir "$T/data/nemesis/apps/jmk-wifi"; pre; check "preinstall: our own packages are not 'other projection'" test $RC = 0
# the head unit's tool shell has no printf, sed, awk, head, tail, cut, tr, find, basename, busybox (09-LivePatch 3.4): none in the LP scripts and the tool
bad=$(grep -nE '(^|[ |;(`$])(printf|sed|awk|head|tail|cut|tr|find|basename|busybox)( |$)' "$here/../package/tools/hud-step" "$here/../package/scripts/"*.sh "$here/../package/svc/"*.sh "$here/../package/bin/"*.sh | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | grep -v 'no printf')
check "no command the head unit's tool shell lacks" test -z "$bad"; [ -z "$bad" ] || echo "$bad"
# the ARM lpatch the car runs: its own usage text (strings of the shipped binary) lists its commands; the scripts may call only those (the Mac host build also has odexdex,
# which the first LivePatch HUD used and the car could not run: LY3LOBUL 2026-11-28)
allowed=$(strings -a "$here/../package/tools/lpatch" | python3 -c "
import re,sys
w=set()
for l in sys.stdin:
    if l.lstrip().startswith('usage: lpatch') or l.startswith('       lpatch '):
        w.update(re.findall(r'(?:lpatch|\|) ([a-z0-9]+) <', l))
print(' '.join(sorted(w)))")
check "the shipped lpatch's usage lists its commands (check apply md5 delta zipadd)" test "$allowed" = "apply check delta md5 zipadd"
used=$(grep -hoE '"\$(LPATCH|REAL_LPATCH)" [a-z]+' "$here/../package/tools/hud-step" "$here/../package/scripts/"*.sh | sed 's/.* //' | sort -u)
bad=; for w in $used; do case " $allowed " in *" $w "*) ;; *) bad="$bad $w" ;; esac; done
check "every lpatch command the scripts call is one the shipped ARM build has" test -z "$bad"; [ -z "$bad" ] || echo "      not in the shipped usage:$bad"
# the migration's preflight: AutoPlay present and >= 0.5.0, decided before any restore or uninstall; writes nothing
pf() {   # pf <pkg-list text> [installed NEMESIS.data version]: OUT, RC
    car pf A 1.17.1; rm -rf "$T/data/nemesis/apps/jmk-autoplay"
    export PL=$1
    cat > "$T/system/xbin/nemesis" <<'N'
#!/bin/sh
case "$1" in pkg-list) [ -z "$PL" ] || echo "$PL" ;; esac
N
    chmod +x "$T/system/xbin/nemesis"
    if [ -n "$2" ]; then mkdir -p "$T/data/nemesis/apps/jmk-autoplay"; echo "package-version=$2" > "$T/data/nemesis/apps/jmk-autoplay/NEMESIS.data"; fi
    before=$(find "$T" -type f | sort | xargs md5 -r 2>/dev/null | md5 -q 2>/dev/null)
    OUT=$(cd "$PK" && JMK_HUD_TEST_ROOT=$T JMK_LR_SHIMS=$WORK/shims ${PF_SH:-sh} ./scripts/preflight.sh 2>&1); RC=$?
    after=$(find "$T" -type f | sort | xargs md5 -r 2>/dev/null | md5 -q 2>/dev/null)
    WROTE=0; [ "$before" = "$after" ] || WROTE=1
}
for PF_SH in sh $(command -v mksh); do
    s=${PF_SH##*/}
    pf "usb-handler|USB|1|service|1.17.1|x"; check "preflight($s): AutoPlay absent -> refused, one line" test "$RC" = 1 -a "$OUT" != "${OUT#Wireless AutoPlay 0.5 이상이 먼저 필요합니다}"
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.4.4|x"; check "preflight($s): 0.4.4 -> refused" test "$RC" = 1
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.4.99|x"; check "preflight($s): 0.4.99 -> refused" test "$RC" = 1
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.5.0|x"; check "preflight($s): 0.5.0 -> go on" test "$RC" = 0
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.5.1|x"; check "preflight($s): 0.5.1 -> go on" test "$RC" = 0
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.10.0|x"; check "preflight($s): 0.10.0 -> go on (numeric compare)" test "$RC" = 0
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|1.0|x"; check "preflight($s): 1.0 -> go on" test "$RC" = 0
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application||x"; check "preflight($s): no version in the list -> refused" test "$RC" = 1
    pf "" 0.4.4; check "preflight($s): no list, installed NEMESIS.data 0.4.4 -> refused" test "$RC" = 1
    pf "" 0.5.1; check "preflight($s): no list, installed NEMESIS.data 0.5.1 -> go on" test "$RC" = 0
    pf "" ; check "preflight($s): no list and no package -> refused" test "$RC" = 1
    pf "jmk-autoplay|JMK Wireless AutoPlay|0|application|0.5.0|x"; check "preflight($s): touches nothing" test "$WROTE" = 0
done
check "migrate.meta names the preflight; depends carries the same floor" bash -c "grep -q '^preflight=scripts/preflight.sh' '$here/../package/migrate.meta.in' && grep -q '^depends=\"jmk-autoplay@>=0.5.0,' '$here/../package/NEMESIS.data.in'"
# NEMESIS refuses the install when a depends item is missing, before any hook or LivePatch step: the order in NEMESIS's own install code (JMK_NEMESIS_SRC = its native/ dir)
dep=$(grep -E '^depends=' "$here/../package/NEMESIS.data.in")
check "depends names jmk-autoplay as a plain (needed) item, at 0.5.0 or newer" test -n "$(echo "$dep" | tr ',"' '\n\n' | grep -x 'jmk-autoplay@>=0.5.0')"
if [ -f "${JMK_NEMESIS_SRC:-/nonexistent}/pkg.c" ]; then
    order=$(python3 - "$JMK_NEMESIS_SRC/pkg.c" <<'PY'
import re, sys
L = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
def first(pat, after=0):
    for i in range(after, len(L)):
        if re.search(pat, L[i]):
            return i
    return -1
d = first(r'meta_deps_unmet\(&meta')
r = first(r'return 22;', d) if d >= 0 else -1
marks = [r'pkg_compat\(&meta', r'lp_check\(&ini', r'zip_extract\(zip', r'lp_prepare\(id, &ini', r'do_fresh_install\(', r'run_named_hook\(&oldini']
ok = d >= 0 and 0 <= r - d <= 8 and all(first(m, d) > r for m in marks)
print('ordered' if ok else 'wrong d=%d r=%d' % (d, r))
PY
)
    check "NEMESIS install: the depends check returns 22 before the compat, LivePatch, unzip steps and any hook" test "$order" = ordered
    [ "$order" = ordered ] || echo "      $order"
else
    echo "skip  NEMESIS install-order check: JMK_NEMESIS_SRC (NEMESIS native/ dir) not set"
fi
echo "---- $PASS passed, $FAILN failed"; [ $FAILN -eq 0 ]
