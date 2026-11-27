#!/usr/bin/env python3
"""jmk-autoplay-hud 0.2.5 (AGPL-3.0, as this package).
HUD DiPO bridge: a local JMK service (`jmk.core`) decides how the route display proceeds.

    src/tbt/cpend.py <smali tree of an HKMC_DiPO result that already holds com/jmk/hud/EndLog and com/jmk/hud/Keep>

Each place is found exactly once; otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('cpend: ' + msg)


if len(sys.argv) != 2:
    die('usage: cpend.py <smali tree>')
root = sys.argv[1]
for need in ('EndLog', 'Keep'):
    if not os.path.isfile(os.path.join(root, 'com/jmk/hud/%s.smali' % need)):
        die('com/jmk/hud/%s.smali is not in the tree (cpend.sh adds it first)' % need)
G = os.path.join(root, 'com/leafia/kr/LeafiaGuide.smali')
U = os.path.join(root, 'com/daudio/app/dipo/e/u.smali')
C = os.path.join(root, 'com/daudio/app/dipo/e/c.smali')
for f in (U, C):
    if not os.path.isfile(f):
        die('DiPO %s is not in the tree: this step is for an HKMC_DiPO build' % os.path.basename(f))
us = open(U).read()
cs = open(C).read()
if 'Lcom/jmk/hud/EndLog;' in us:
    die('already done')

# 4. the blank
BLANK = re.compile(r'^(\.method private sendHudBlank\(\)V\n    \.registers \d+\n)', re.M)
if len(BLANK.findall(us)) != 1:
    die('sendHudBlank found %d times (want 1)' % len(BLANK.findall(us)))
us = BLANK.sub(lambda m: m.group(1) + '\n    invoke-static {}, Lcom/jmk/hud/EndLog;->blank()V\n', us, count=1)

# 2. the state 0 branch
ZERO = re.compile(r'(    invoke-static \{p2\}, Lcom/daudio/app/dipo/e/c;->a\(Lcom/daudio/app/dipo/e/c;\)I\n\n    move-result v3\n\n'
                  r'    if-nez v3, :cond_[0-9a-f]+\n\n)(    invoke-virtual \{p0\}, Lcom/daudio/app/dipo/e/u;->nS\(\)V\n\n    goto :(goto_[0-9a-f]+)\n)')
zm = ZERO.findall(us)
if len(zm) != 1:
    die('the state 0 branch was found %d times (want 1)' % len(zm))
us = ZERO.sub(lambda m: m.group(1) + '    invoke-static {p0}, Lcom/jmk/hud/Keep;->zero(Ljava/lang/Object;)I\n\n    move-result v3\n\n'
              '    if-nez v3, :%s\n\n' % m.group(3) + m.group(2), us, count=1)

# 1. the state is stored
STATE = re.compile(r'(    aget v0, v0, v2\n\n    iput v0, p0, Lcom/daudio/app/dipo/e/c;->aR:I\n)')
if len(STATE.findall(cs)) != 1:
    die('the place the state is stored was found %d times (want 1)' % len(STATE.findall(cs)))
cs = STATE.sub(lambda m: m.group(1) + '\n    invoke-static {v0}, Lcom/jmk/hud/Keep;->state(I)V\n', cs, count=1)

# 3. the bridge build's check
gs = body = newbody = None
if os.path.isfile(G):
    gs = open(G).read()
    HEAD = re.compile(r'^\.method static beat0\(\)V\n.*?^\.end method\n', re.S | re.M)
    found = HEAD.findall(gs)
    if len(found) != 1:
        die('beat0 found %d times (want 1)' % len(found))
    body = found[0]
    PAT = re.compile(r'(    iget v6, v5, Lcom/leafia/kr/LeafiaGuide\$Pub;->live:I\n\n    if-ne v6, v4, (:cond_[0-9a-f]+)\n\n)'
                     r'(    invoke-static \{\}, Lcom/leafia/kr/LeafiaGuide;->now\(\)J\n)')
    END = re.compile(r'(:cond_[0-9a-f]+)\n    iget-object v6, v5, Lcom/leafia/kr/LeafiaGuide\$Pub;->role:Ljava/lang/String;\n\n'
                     r'    const-string v7, "guide lost: no TBT for 60 s"\n')
    hits = PAT.findall(body)
    ends = END.findall(body)
    if len(hits) != 1 or len(ends) != 1:
        die('the place in beat0 was found %d times, the end of it %d (want 1 and 1)' % (len(hits), len(ends)))
    stay, end = hits[0][1], ends[0]
    newbody = PAT.sub(lambda m: m.group(1)
                      + '    sget-object v6, Lcom/leafia/kr/LeafiaGuide;->CP:Lcom/leafia/kr/LeafiaGuide$Pub;\n\n'
                      '    if-ne v5, v6, :cond_jmk_other\n\n'
                      '    invoke-static {}, Lcom/leafia/kr/LeafiaGuide;->now()J\n\n    move-result-wide v6\n\n'
                      '    iget-wide v8, v5, Lcom/leafia/kr/LeafiaGuide$Pub;->lastTbt:J\n\n    sub-long/2addr v6, v8\n\n'
                      '    invoke-static {v6, v7}, Lcom/jmk/hud/Keep;->beat(J)I\n\n    move-result v6\n\n'
                      '    if-eqz v6, %s\n\n    goto %s\n\n    :cond_jmk_other\n' % (stay, end) + m.group(3), body, count=1)

open(U, 'w').write(us)
open(C, 'w').write(cs)
if gs is not None:
    open(G, 'w').write(gs.replace(body, newbody, 1))
print('cpend: %sthe state 0 branch and the state store are hooked; the blank path is named in the log'
      % ('the check of the build is hooked; ' if gs is not None else ''))
