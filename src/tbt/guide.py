#!/usr/bin/env python3
"""jmk-autoplay-hud 0.2.2 (AGPL-3.0, as this package): Android Auto turn-by-turn is no longer switched off by silence.

    src/tbt/guide.py <smali tree of an HKMC_GPM result>

The periodic check of the GPM build (LeafiaGuide.beat0) ended an Android Auto guidance when the phone sent no turn or distance
message for 60 seconds. On a long straight road the navigation app sends nothing new for longer, so the cluster and the HUD
went off and on again. For Android Auto this step leaves that time rule out: the guidance ends when the session ends or the phone
ends its guidance (releaseGuidance and the navigation bridge, unchanged). CarPlay keeps its rule.

One place, found exactly once in LeafiaGuide.beat0; otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('guide: ' + msg)


if len(sys.argv) != 2:
    die('usage: guide.py <smali tree>')
root = sys.argv[1]
F = os.path.join(root, 'com/leafia/kr/LeafiaGuide.smali')
if not os.path.isfile(F):
    die('no com/leafia/kr/LeafiaGuide.smali in %s' % root)
if os.path.isdir(os.path.join(root, 'com/daudio/app/dipo')):
    die('a DiPO build: this step is for HKMC_GPM')
src = open(F).read()
HEAD = re.compile(r'^\.method static beat0\(\)V\n.*?^\.end method\n', re.S | re.M)
found = HEAD.findall(src)
if len(found) != 1:
    die('beat0 found %d times (want 1)' % len(found))
body = found[0]
if 'AA:Lcom/leafia/kr/LeafiaGuide$Pub;\n\n    if-eq v5, v6' in body:
    die('already done')
PAT = re.compile(r'(    iget v6, v5, Lcom/leafia/kr/LeafiaGuide\$Pub;->live:I\n\n    if-ne v6, v4, (:cond_[0-9a-f]+)\n\n)'
                 r'(    invoke-static \{\}, Lcom/leafia/kr/LeafiaGuide;->now\(\)J\n)')
hits = PAT.findall(body)
if len(hits) != 1 or body.count('"guide lost: no TBT for 60 s"') != 1:
    die('the place was found %d times (want 1)' % len(hits))
new = PAT.sub(lambda m: m.group(1) + '    sget-object v6, Lcom/leafia/kr/LeafiaGuide;->AA:Lcom/leafia/kr/LeafiaGuide$Pub;\n\n'
              '    if-eq v5, v6, %s\n\n' % m.group(2) + m.group(3), body, count=1)
open(F, 'w').write(src.replace(body, new, 1))
print('guide: Android Auto is left out of the 60 s rule')
