#!/usr/bin/env python3
"""jmk-autoplay-hud 0.2.6 (AGPL-3.0, as this package). Wireless CarPlay keeps the phone's Bluetooth connected.

    src/tbt/btkeep.py <smali tree of an HKMC_DiPO bridge result that already holds com/jmk/hud/BtKeep>

Each place is found exactly once; otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('btkeep: ' + msg)


if len(sys.argv) != 2:
    die('usage: btkeep.py <smali tree>')
root = sys.argv[1]
if not os.path.isfile(os.path.join(root, 'com/jmk/hud/BtKeep.smali')):
    die('com/jmk/hud/BtKeep.smali is not in the tree (btkeep.sh adds it first)')
C = os.path.join(root, 'com/daudio/app/dipo/f/c.smali')
O = os.path.join(root, 'com/ev6/cpwl/LeafiaProjectionOwner.smali')
for f in (C, O):
    if not os.path.isfile(f):
        die('%s is not in the tree: this step is for an HKMC_DiPO bridge build' % os.path.relpath(f, root))
cs = open(C).read()
os_ = open(O).read()
if 'Lcom/jmk/hud/BtKeep;' in cs:
    die('already done')
G = re.compile(r'(\.method public final g\(Z\)Z\n    \.registers \d+\n)')
if len(G.findall(cs)) != 1 or len(re.findall(r'\.method private declared-synchronized B\(I\)V', cs)) != 1:
    die('g(Z) or B(I) was not found exactly once')
cs = G.sub(lambda m: m.group(1) + '\n    invoke-static {p1}, Lcom/jmk/hud/BtKeep;->keep(Z)Z\n\n    move-result v0\n\n    if-eqz v0, :cond_jmk_bt\n\n'
           '    const/4 v0, 0x1\n\n    invoke-direct {p0, v0}, Lcom/daudio/app/dipo/f/c;->B(I)V\n\n    return v0\n\n    :cond_jmk_bt\n', cs, count=1)
for name, call in (('started', 'start'), ('finalized', 'end')):
    pat = re.compile(r'(\.method public static %s\(Lcom/daudio/app/dipo/telechips/CarPlayService;I\)V\n    \.registers \d+\n)' % name)
    if len(pat.findall(os_)) != 1:
        die('%s(CarPlayService, int) was not found exactly once' % name)
    os_ = pat.sub(lambda m: m.group(1) + '\n    invoke-static {p1}, Lcom/jmk/hud/BtKeep;->%s(I)V\n' % call, os_, count=1)
open(C, 'w').write(cs)
open(O, 'w').write(os_)
print('btkeep: g(Z), started and finalized are hooked')
