#!/usr/bin/env python3
"""jmk-autoplay-hud 0.2.2 (AGPL-3.0, as this package): the length of every text handed to the cluster interface goes into the log.

    src/tbt/textlog.py <smali tree of an HKMC_GPM or HKMC_DiPO result that already holds com/jmk/hud/TextLog>

In front of each place where the stock code puts a turn-list, crossing or destination name into the cluster interface, and after the
list frame's text is turned into bytes, one static call tells com.jmk.hud.TextLog the string (and for the frame its byte count).
Nothing else changes; the text is not logged, only its lengths. Each place is found by its instruction text; the counts must be
those of the build (a GPM or a DiPO bridge result), otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('textlog: ' + msg)


if len(sys.argv) != 2:
    die('usage: textlog.py <smali tree>')
root = sys.argv[1]
if not os.path.isfile(os.path.join(root, 'com/jmk/hud/TextLog.smali')):
    die('com/jmk/hud/TextLog.smali is not in the tree (textlog.sh adds it first)')
cands = [os.path.join(root, 'com/google/android/projection/sink/navigation/GpmNaviTBTManager.smali'),
         os.path.join(root, 'com/daudio/app/dipo/e/u.smali')]
files = [c for c in cands if os.path.isfile(c)]
if len(files) != 1:
    die('neither or both of GpmNaviTBTManager and DiPO e/u in the tree')
F = files[0]
GPM = F.endswith('GpmNaviTBTManager.smali')
WANT = {'turn': 1, 'dest': 2, 'cross': 1 if GPM else 2, 'hud': 1}
src = open(F).read()
if 'Lcom/jmk/hud/TextLog;' in src:
    die('already done')
counts = {}
for kind, cls in (('turn', 'TurnList'), ('dest', 'DestinationName'), ('cross', 'CrossroadName')):
    pat = re.compile(r'^(    )iput-object ([vp]\d+), [vp]\d+, Lcom/hkmc/cluster/NavigationCluster\$%s;->name:Ljava/lang/String;\n' % cls, re.M)
    src, n = pat.subn(lambda m: '%sinvoke-static {%s}, Lcom/jmk/hud/TextLog;->%s(Ljava/lang/String;)V\n\n%s' % (m.group(1), m.group(2), kind, m.group(0)), src)
    counts[kind] = n
# the list frame: the string register of getBytes("UTF-16LE"), then the byte count after array-length
HUD = re.compile(r'(    invoke-virtual \{(v\d+), v\d+\}, Ljava/lang/String;->getBytes\(Ljava/lang/String;\)\[B\n(?:.*\n){1,14}?    array-length (v\d+), v\d+\n)')
src, n = HUD.subn(lambda m: m.group(1) + '\n    invoke-static {%s, %s}, Lcom/jmk/hud/TextLog;->hud(Ljava/lang/String;I)V\n' % (m.group(2), m.group(3)), src)
counts['hud'] = n
if counts != WANT:
    die('the places found %r, wanted %r (nothing written)' % (counts, WANT))
open(F, 'w').write(src)
print('textlog: %s' % ', '.join('%s %d' % kv for kv in sorted(counts.items())))
