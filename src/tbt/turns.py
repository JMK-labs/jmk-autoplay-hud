#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.34 (AGPL-3.0, as this package): the turn pictures of the cluster / HUD as the stock Korean
navigation draws them (com/jmk/hud/Turns.java decides, TurnsOut.java is the hooks' side).

    src/tbt/turns.py <gpm|dipo> <smali tree>

Leafia's turn code stays; these hooks change only what Turns lists. Per app:

  gpm   HKMC_GPM (Android Auto; a 0.1.33 result: GpmNaviTBTManager, com/leafia/kr, com/jmk/hud/Near with window()):
          1. GpmNaviTBTManager.setRampDisplayType, in front of its one return:
             mDisplayType = TurnsOut.aaFar(event, side, mDisplayType)       (on-ramp 161 / 162 / 160, off-ramp 164 / 165 / 163);
          2. LeafiaTurn.standard, in front of LeafiaStandard.format (same arguments): TurnsOut.aaNear(...); a result is
             returned as the near layout (on-ramp, fork), null goes on to LeafiaStandard.format;
          3. GpmNaviTBTManager.updateTBTInfo, after BarOut.aa, before the one updateTBTInfo send:
             direction = TurnsOut.aaDir(result, direction); TurnsOut.aaIn(mTurnAngle, mDisplayType);
             TurnsOut.aaOut(mEvent, mTurnSide, display type, direction)      (the log line).
  dipo  HKMC_DiPO bridge build (CarPlay; a 0.1.33 result: e/u.smali, com/leafia/kr, com/jmk/hud/Near with window()):
          1. u.a, the one LeafiaCpStandard.projection call: the number before it is kept, after it
             icon = TurnsOut.cpFar(u, component, route guidance, number before, number after);
          2. LeafiaCpStandard.format, after its nativeTurn call: native = TurnsOut.cpNear(native, facts);
          3. u.a, in front of jmkMark (before the one updateTBTInfo send): TurnsOut.cpSent(far icon, display type,
             direction)                                                       (the log line).
        LeafiaCpStandard.facts(Object, Object, Object) must be there (TurnsOut reads it by reflection).
        The turn-by-turn-only DiPO build (no com/leafia/kr) has no projection and no near layout: refused.

Each place must be found exactly once and the Turns hooks not be there yet; otherwise nothing is written and the exit
status is 1 (the profile keeps its earlier build). The Turns classes themselves are added by the caller (src/tbt/turns.sh).
"""
import os
import re
import sys


def die(msg):
    sys.exit('turns: ' + msg)


if len(sys.argv) != 3 or sys.argv[1] not in ('gpm', 'dipo'):
    die('usage: turns.py <gpm|dipo> <smali tree>')
kind, root = sys.argv[1], sys.argv[2]
out = {}
TO = 'Lcom/jmk/hud/TurnsOut;'


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


def need_near():
    if '.method public static window()I' not in text('com/jmk/hud/Near.smali'):
        die('com/jmk/hud/Near is not the 0.1.33 one (no window()): not a 0.1.33 result')
    for dp, _, names in os.walk(root):
        for n in names:
            if n.endswith('.smali') and not dp.endswith(os.path.join('com', 'jmk', 'hud')):
                with open(os.path.join(dp, n)) as f:
                    if TO in f.read():
                        die('%s already has the Turns hooks' % os.path.relpath(os.path.join(dp, n), root))


if kind == 'gpm':
    F = 'com/google/android/projection/sink/navigation/GpmNaviTBTManager.smali'
    M = 'Lcom/google/android/projection/sink/navigation/GpmNaviTBTManager;'
    text(F)
    need_near()

    def ramp(body):
        if '    .registers 5\n' not in body:
            die('setRampDisplayType: not .registers 5')
        ret = '    return-void\n'
        new = ('    iget v0, p0, %s->mDisplayType:I\n\n'
               '    invoke-static {p1, p2, v0}, %s->aaFar(III)I\n\n'
               '    move-result v0\n\n'
               '    iput v0, p0, %s->mDisplayType:I\n\n' % (M, TO, M)) + ret
        return replace_once(body, ret, new, 'setRampDisplayType return-void')
    set_method(F, '.method private setRampDisplayType(II)V', ramp)

    def upd(body):
        old = ('    invoke-static {v5}, Lcom/jmk/hud/BarOut;->aa([I)V\n\n'
               '    const/4 v5, 0x0\n\n'
               '    const/4 v6, 0x0\n\n'
               '    invoke-virtual/range {v0 .. v9}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n')
        new = ('    invoke-static {v5}, Lcom/jmk/hud/BarOut;->aa([I)V\n\n'
               '    invoke-static {v5, v3}, %s->aaDir([IF)F\n\n'
               '    move-result v3\n\n'
               '    iget v5, p0, %s->mTurnAngle:I\n\n'
               '    iget v6, p0, %s->mDisplayType:I\n\n'
               '    invoke-static {v5, v6}, %s->aaIn(II)V\n\n'
               '    iget v5, p0, %s->mEvent:I\n\n'
               '    iget v6, p0, %s->mTurnSide:I\n\n'
               '    invoke-static {v5, v6, v1, v3}, %s->aaOut(IIIF)V\n\n' % (TO, M, M, TO, M, M, TO)) + old.split('\n\n', 1)[1]
        return replace_once(body, old, new, 'updateTBTInfo: BarOut.aa in front of the updateTBTInfo send')
    set_method(F, '.method private updateTBTInfo()V', upd)
    for fld in ('mTurnAngle', 'mDisplayType', 'mEvent', 'mTurnSide'):
        if out[F].count('.field private %s:I\n' % fld) != 1:
            die('GpmNaviTBTManager field %s:I found %d times (want 1)' % (fld, out[F].count('.field private %s:I\n' % fld)))

    T = 'com/leafia/kr/LeafiaTurn.smali'

    def std(body):
        if '    .registers 6\n' not in body or body.count('    const/4 p3, 0x0\n') != 1 or body.count('    return-object p3\n') != 1:
            die('LeafiaTurn.standard: not the known shape (.registers 6, p3 = null returned when it has no result)')
        old = '    invoke-static {v0, p2, p0, p1, v1}, Lcom/leafia/kr/LeafiaStandard;->format(IIIII)[I\n'
        new = ('    invoke-static {v0, p2, p0, p1, v1}, %s->aaNear(IIIII)[I\n\n'
               '    move-result-object p3\n\n'
               '    if-eqz p3, :jmk_turns_leafia\n\n'
               '    return-object p3\n\n'
               '    :jmk_turns_leafia\n' % TO) + old
        return replace_once(body, old, new, 'LeafiaTurn.standard: the LeafiaStandard.format call')
    set_method(T, '.method public static standard(IFFI)[I', std)
    summary = 'setRampDisplayType aaFar, LeafiaTurn.standard aaNear, updateTBTInfo aaDir + aaIn + aaOut'
else:
    F = 'com/daudio/app/dipo/e/u.smali'
    C = 'com/leafia/kr/LeafiaCpStandard.smali'
    if not os.path.isfile(path(C)):
        die('no %s: a turn-by-turn-only build (no projection, no near layout)' % C)
    text(F)
    need_near()
    c = text(C)
    if c.count('.method private static facts(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)[I\n') != 1:
        die('LeafiaCpStandard.facts(Object, Object, Object)[I found %d times (want 1)'
            % c.count('.method private static facts(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)[I\n'))

    def fmt(body):
        old = ('    invoke-static/range {v2 .. v7}, Lcom/leafia/kr/LeafiaCpStandard;->nativeTurn(IIIIZI)[I\n\n'
               '    move-result-object v2\n')
        if body.count('    invoke-static {p0, p1, p2}, Lcom/leafia/kr/LeafiaCpStandard;->facts(Ljava/lang/Object;Ljava/lang/Object;'
                      'Ljava/lang/Object;)[I\n\n    move-result-object p0\n') != 1:
            die('LeafiaCpStandard.format: the facts in p0 found %d times (want 1)' % body.count('->facts('))
        return replace_once(body, old, old + '\n    invoke-static {v2, p0}, %s->cpNear([I[I)[I\n\n    move-result-object v2\n' % TO,
                            'LeafiaCpStandard.format: the nativeTurn call')
    set_method(C, '.method public static declared-synchronized format(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;I)[I', fmt)

    s = text(F)
    proj = ('    invoke-static {p0, p1, p2, v1}, Lcom/leafia/kr/LeafiaCpStandard;->projection(Ljava/lang/Object;Ljava/lang/Object;'
            'Ljava/lang/Object;I)I\n\n'
            '    move-result v1\n\n'
            '    iget-object v0, p0, Lcom/daudio/app/dipo/e/u;->Ak:Lcom/hkmc/cluster/NavigationCluster;\n')
    s = replace_once(s, proj, '    move v2, v1\n\n' + proj.replace(
        '    move-result v1\n\n',
        '    move-result v1\n\n'
        '    invoke-static {p0, p1, p2, v2, v1}, %s->cpFar(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;II)I\n\n'
        '    move-result v1\n\n' % TO, 1), 'u.a: the LeafiaCpStandard.projection call')
    mark = ('    invoke-direct {p0, v1}, Lcom/daudio/app/dipo/e/u;->jmkMark(I)V\n\n'
            '    invoke-static {v1, v8}, Lcom/jmk/hud/BarOut;->cp(II)V\n\n'
            '    invoke-virtual/range {v0 .. v9}, Lcom/hkmc/cluster/NavigationCluster;->updateTBTInfo(IIFFIIIII)V\n\n'
            '    move v1, v10\n')
    s = replace_once(s, mark, '    invoke-static {v10, v1, v3}, %s->cpSent(IIF)V\n\n' % TO + mark, 'u.a: jmkMark in front of the updateTBTInfo send')
    if s.count('    move v10, v1\n\n    invoke-static {p0, p1, p2, v1}, Lcom/leafia/kr/LeafiaCpStandard;->format(') != 1:
        die('u.a: the far icon kept in v10 in front of LeafiaCpStandard.format found %d times (want 1)'
            % s.count('    move v10, v1\n\n    invoke-static {p0, p1, p2, v1}, Lcom/leafia/kr/LeafiaCpStandard;->format('))
    out[F] = s
    summary = 'u.a cpFar (after projection) + cpSent (before the send), LeafiaCpStandard.format cpNear'

for rel, s in out.items():
    with open(path(rel), 'w') as f:
        f.write(s)
print('turns: %s: %s' % (kind, summary))
