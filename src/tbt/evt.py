#!/usr/bin/env python3
"""jmk-autoplay-hud 0.3.2 (AGPL-3.0, as this package). Counting lines and a guarded restart in the wireless CarPlay build.

    src/tbt/evt.py <smali tree of an HKMC_DiPO bridge result that already holds com/jmk/hud/Evt>

  1. com/ev6/cpwl/Bridge: before each of the three calls that hand bytes from the phone to the car's iAP2 service (Iap2SvcTransportReadDone),
     Evt.iapIn(bytes, length) counts the lane messages (0x5204). Nothing is kept of the bytes.
  2. com/daudio/app/dipo/e/u: where the route's source name is stored, Evt.source(name) keeps it for the counting line (a token or a hash).
  3. com/daudio/app/dipo/e/LeafiaRgRestart.run: the restart after a source change runs through Evt.restart (a catch of its own, a line for each step).

Each place is found exactly once; otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('evt: ' + msg)


if len(sys.argv) != 2:
    die('usage: evt.py <smali tree>')
root = sys.argv[1]
if not os.path.isfile(os.path.join(root, 'com/jmk/hud/Evt.smali')):
    die('com/jmk/hud/Evt.smali is not in the tree (evt.sh adds it first)')
B = os.path.join(root, 'com/ev6/cpwl/Bridge.smali')
U = os.path.join(root, 'com/daudio/app/dipo/e/u.smali')
R = os.path.join(root, 'com/daudio/app/dipo/e/LeafiaRgRestart.smali')
for f in (B, U, R):
    if not os.path.isfile(f):
        die('%s is not in the tree: this step is for an HKMC_DiPO bridge build' % os.path.relpath(f, root))
bs, us, rs = open(B).read(), open(U).read(), open(R).read()
if 'Lcom/jmk/hud/Evt;' in bs or 'Lcom/jmk/hud/Evt;' in us or 'Lcom/jmk/hud/Evt;' in rs:
    die('already done')

# 1. the three hand-overs to the iAP2 service: (the byte array register, the length register) per call
for regs in (('p0', 'v0', 'v3'), ('v1', 'v0', 'p2'), ('v1', 'p1', 'p2')):
    line = '    invoke-interface {%s, %s, %s}, Lcom/tcc/iap2/IIap2Service;->Iap2SvcTransportReadDone([BI)Z\n' % regs
    if bs.count(line) != 1:
        die('the hand-over %s was found %d times (want 1)' % (regs, bs.count(line)))
    bs = bs.replace(line, '    invoke-static {%s, %s}, Lcom/jmk/hud/Evt;->iapIn([BI)V\n\n' % (regs[1], regs[2]) + line, 1)

# 2. the source name store
SRC = '    iput-object v4, p0, Lcom/daudio/app/dipo/e/u;->leafiaSource:Ljava/lang/String;\n'
if us.count(SRC) != 1:
    die('the source name store was found %d times (want 1)' % us.count(SRC))
us = us.replace(SRC, SRC + '\n    invoke-static {v4}, Lcom/jmk/hud/Evt;->source(Ljava/lang/String;)V\n', 1)

# 3. the restart
RUN = '    invoke-virtual {v0}, Lcom/daudio/app/dipo/e/b;->leafiaRestartRouteGuidance()V\n'
if rs.count(RUN) != 1:
    die('the restart call was found %d times (want 1)' % rs.count(RUN))
rs = rs.replace(RUN, '    invoke-static {v0}, Lcom/jmk/hud/Evt;->restart(Ljava/lang/Object;)V\n', 1)

open(B, 'w').write(bs)
open(U, 'w').write(us)
open(R, 'w').write(rs)
print('evt: the lane count, the source name and the guarded restart are hooked')
