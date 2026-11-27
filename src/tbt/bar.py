#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.33 (AGPL-3.0, as this package): the cluster's near-turn distance bar from the phone's guidance
(com/jmk/hud/Bar.java, BarOut.java, NaviBar.java, and Near.java extended to the stock distance D).

    src/tbt/bar.py <gpm|dipo|navi> <smali tree>

The cluster draws the bar from the trap-info frame, which only the stock navigation (HKMC_Navi_ExSL) sends; the phone
processes tell their bar to it by broadcast (com.jmk.hud.BAR) and it replaces the bar field of its frames. Per app:

  gpm   HKMC_GPM (Android Auto; the tree with GpmNaviTBTManager and Leafia's com/leafia/kr, whose near-turn hooks of
        0.1.11 call com.jmk.hud.Near, already extended by the caller):
          1. LeafiaStandard.bar / format / stock: the window constant 457 (0x1c9) is read from Near.window() (the stock
             D of the turn Near just looked at: 350 m, 1050 m for an expressway turn);
          2. GpmNaviTBTManager.updateTBTInfo: BarOut.aa(result of LeafiaTurn.standard) in front of the updateTBTInfo send
             (the one turn frame; null result = none: no phone bar);
          3. GpmNaviTBTManager.releaseGuidance: BarOut.end() first (guidance released: no phone bar).
  dipo  HKMC_DiPO bridge build (CarPlay; the tree with e/u.smali and Leafia's com/leafia/kr):
          1. the same LeafiaStandard window;
          2. u.a (the route guidance update): BarOut.cp(display type, bar) after jmkMark, before updateTBTInfo;
          3. u.jmkRelease: BarOut.end() first.
        The turn-by-turn-only DiPO build (no com/leafia/kr, bar always 0, no near layout) has nothing to hook: refused.
  navi  HKMC_Navi_ExSL: in front of every trap-info call the stock sender makes (updateTBTTrapInfoNew, three; the
        17-int updateTBTTrapInfo in message/a, one) NaviBar.info / NaviBar.trap17 give the bar to send, NaviBar.after()
        follows the call. The 17-int call in NaviSpecialReceiver (the all-zero clear frame the head unit sends when it
        wakes) is left as it is.

Each place must be found exactly once (the navigation: the counts above) and the Bar classes not be there yet;
otherwise nothing is written and the exit status is 1 (the profile keeps its earlier build). The Bar classes themselves
are added by the caller (src/tbt/bar.sh).
"""
import os
import re
import sys


def die(msg):
    sys.exit('bar: ' + msg)


if len(sys.argv) != 3 or sys.argv[1] not in ('gpm', 'dipo', 'navi'):
    die('usage: bar.py <gpm|dipo|navi> <smali tree>')
kind, root = sys.argv[1], sys.argv[2]
out = {}


def path(rel):
    return os.path.join(root, rel)


def text(rel):
    if rel not in out:
        if not os.path.isfile(path(rel)):
            die('no %s in %s' % (rel, root))
        out[rel] = open(path(rel)).read()
    return out[rel]


def method(body, header):
    pat = re.compile(r'^' + re.escape(header) + r'\n.*?^\.end method\n', re.S | re.M)
    found = pat.findall(body)
    if len(found) != 1:
        die('%s found %d times (want 1)' % (header, len(found)))
    return found[0]


def replace_once(body, old, new, what):
    if body.count(old) != 1:
        die('%s found %d times (want 1)' % (what, body.count(old)))
    return body.replace(old, new, 1)


def set_method(rel, header, fn):
    s = text(rel)
    old = method(s, header)
    out[rel] = s.replace(old, fn(old), 1)


def leafia_window():
    """LeafiaStandard: 457 -> Near.window() in bar, format and stock"""
    rel = 'com/leafia/kr/LeafiaStandard.smali'
    s = text(rel)
    if not s.startswith('.class public final Lcom/leafia/kr/LeafiaStandard;\n'):
        die('LeafiaStandard class not found')
    near = text('com/jmk/hud/Near.smali')
    if '.method public static window()I' not in near:
        die('com/jmk/hud/Near is not the 0.1.33 one (no window())')
    for h in ('.method static bar(I)I', '.method static format(IIIII)[I', '.method static stock(IIIII)[I'):
        def fix(body):
            m = re.findall(r'^    const/16 (v\d+), 0x1c9\n', body, re.M)
            if len(m) != 1:
                die('%s: window constant 0x1c9 found %d times (want 1)' % (h, len(m)))
            return body.replace('    const/16 %s, 0x1c9\n' % m[0],
                                '    invoke-static {}, Lcom/jmk/hud/Near;->window()I\n\n    move-result %s\n' % m[0], 1)
        set_method(rel, h, fix)


BO = 'Lcom/jmk/hud/BarOut;'
NB = 'Lcom/jmk/hud/NaviBar;'

if kind == 'gpm':
    F = 'com/google/android/projection/sink/navigation/GpmNaviTBTManager.smali'
    if 'Lcom/jmk/hud/BarOut;' in text(F):
        die('%s already has the Bar hooks' % F)
    leafia_window()

    def upd(body):
        pat = re.compile(r'(Lcom/leafia/kr/LeafiaTurn;->standard\(IFFI\)\[I\n\n    move-result-object (v\d+)\n\n'
                         r'    if-eqz \2, (:cond_\w+)\n.*?\n    \3\n)(?=(?:.*\n){0,8}?    invoke-virtual/range \{v0 \.\. v9\}, '
                         r'Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo\(IIFFIIIII\)V\n)', re.S)
        m = pat.findall(body)
        if len(m) != 1:
            die('GpmNaviTBTManager.updateTBTInfo: LeafiaTurn.standard result before the send found %d times (want 1)' % len(m))
        return pat.sub(lambda x: x.group(1) + '    invoke-static {%s}, %s->aa([I)V\n\n' % (x.group(2), BO), body, count=1)
    set_method(F, '.method private updateTBTInfo()V', upd)
    set_method(F, '.method private releaseGuidance()V', lambda b: replace_once(
        b, '    .registers 12\n\n', '    .registers 12\n\n    invoke-static {}, %s->end()V\n\n' % BO, 'releaseGuidance .registers 12'))
    summary = 'LeafiaStandard window, updateTBTInfo aa, releaseGuidance end'
elif kind == 'dipo':
    F = 'com/daudio/app/dipo/e/u.smali'
    if not os.path.isfile(path('com/leafia/kr/LeafiaStandard.smali')):
        die('no com/leafia/kr/LeafiaStandard.smali: a turn-by-turn-only build (no near layout, no bar)')
    if 'Lcom/jmk/hud/BarOut;' in text(F):
        die('%s already has the Bar hooks' % F)
    leafia_window()
    s = text(F)
    if s.count('    const/4 v5, 0x2\n\n    aget v8, v11, v5\n') != 1:
        die('the bar of the format result (aget v8, v11) found %d times (want 1)' % s.count('    const/4 v5, 0x2\n\n    aget v8, v11, v5\n'))
    mark = ('    invoke-direct {p0, v1}, Lcom/daudio/app/dipo/e/u;->jmkMark(I)V\n\n'
            '    invoke-virtual/range {v0 .. v9}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n')
    out[F] = replace_once(s, mark, mark.replace('\n\n    invoke-virtual/range', '\n\n    invoke-static {v1, v8}, %s->cp(II)V\n\n    invoke-virtual/range' % BO, 1),
                          'the updateTBTInfo send after jmkMark')
    set_method(F, '.method private jmkRelease()V', lambda b: replace_once(
        b, '    .registers 2\n\n', '    .registers 2\n\n    invoke-static {}, %s->end()V\n\n' % BO, 'jmkRelease .registers 2'))
    summary = 'LeafiaStandard window, u.a cp, u.jmkRelease end'
else:
    base = os.path.join(root, 'com/mnsoft/navi')
    if not os.path.isdir(base):
        die('no com/mnsoft/navi in %s' % root)
    new_re = re.compile(r'^    invoke-virtual \{(v\d+), (v\d+)\}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTTrapInfoNew'
                        r'\(Lcom/hkmc/cluster/NavigationCluster\$NaviTbtTrapInfo;\)V\n', re.M)
    int_re = re.compile(r'^    invoke-virtual/range \{v(\d+) \.\. v(\d+)\}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTTrapInfo'
                        r'\(IIIIIIIIIIIIIIIII\)V\n', re.M)
    n_new = n_int = n_skip = 0
    for dp, _, names in os.walk(base):
        for n in sorted(names):
            if not n.endswith('.smali'):
                continue
            rel = os.path.relpath(os.path.join(dp, n), root)
            s = text(rel)
            if 'Lcom/jmk/hud/NaviBar;' in s:
                die('%s already has the Bar hooks' % rel)
            if rel.endswith('message/dynamic/NaviSpecialReceiver.smali'):
                n_skip += len(int_re.findall(s)) + len(new_re.findall(s))
                continue

            def sub_new(m):
                c, o = m.group(1), m.group(2)
                return ('    invoke-static {%s, %s}, %s->info(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n\n'
                        '    move-result-object %s\n\n'
                        '    check-cast %s, Lcom/hkmc/cluster/NavigationCluster$NaviTbtTrapInfo;\n\n'
                        '%s\n    invoke-static {}, %s->after()V\n') % (c, o, NB, o, o, m.group(0), NB)

            def sub_int(m):
                a, b = int(m.group(1)), int(m.group(2))
                if b - a != 17:
                    die('%s: the 17-int call spans v%d..v%d (want 18 registers)' % (rel, a, b))
                return ('    invoke-static/range {v%d .. v%d}, %s->trap17(Ljava/lang/Object;IIIIIIIIIIIIIIIII)I\n\n'
                        '    move-result v%d\n\n'
                        '%s\n    invoke-static {}, %s->after()V\n') % (a, b, NB, a + 12, m.group(0), NB)
            s2, c1 = new_re.subn(sub_new, s)
            s2, c2 = int_re.subn(sub_int, s2)
            if c1 or c2:
                out[rel] = s2
                n_new += c1
                n_int += c2
    if (n_new, n_int, n_skip) != (3, 1, 1):
        die('trap-info call sites: object form %d (want 3), 17-int form %d (want 1), the wake-up clear frame %d (want 1)' % (n_new, n_int, n_skip))
    summary = 'trap-info sites: object %d, 17-int %d (wake-up clear frame left)' % (n_new, n_int)

for rel, s in out.items():
    with open(path(rel), 'w') as f:
        f.write(s)
print('bar: %s: %s' % (kind, summary))
