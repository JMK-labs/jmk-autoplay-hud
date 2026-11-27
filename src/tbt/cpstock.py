#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.36 (AGPL-3.0, as this package): the turn-by-turn-only HKMC_DiPO build gets the stock Korean
CarPlay far-icon numbers back in its table.

    src/tbt/cpstock.py <smali tree of a turn-by-turn-only DiPO result>

The turn-by-turn-only DiPO builds (no com/leafia, no projection, no near layout, no com/jmk/hud/Turns: 0.1.34's Turns
hooks cannot go there) carry the Korean-firmware mod code base's CarPlay table with its US numbers. The table is the big
switch of com/daudio/app/dipo/e/u.a(Integer, Object). This step puts back, in that switch's constants only, the numbers
the car's own stock DiPO has (the same firmware's stock copy gives each of them; test/check-scripts.sh compares them):

  type 9  on-ramp                      172 (0xac) -> 160 (0xa0)
  type 22 expressway exit left          82 (0x52) -> 165 (0xa5)
  type 23 expressway exit right         81 (0x51) -> 164 (0xa4)
  the eight left-hand-traffic roundabout rows (driving side 1, roundabout junction 1; the A family 96..107 came
  from the mod code base, the stock rows are 192..203):
      0 degrees 0x61 -> 0xc1,  90 0x63 -> 0xc3,  120 0x64 -> 0xc4,  180 0x66 -> 0xc6,
      -120 0x68 -> 0xc8,  -90 0x69 -> 0xc9,  -30 0x6b -> 0xcb,  the type-31 row 0x60 -> 0xc0

Nothing else: no gap filling, no bands, no near layout, no hook, no new class, no log line. Each place is found exactly
once (the text around the constant, labels left open) and holds the mod code base's number; otherwise nothing is written
and the exit status is 1 (that result keeps its build). A bridge build (com/leafia, Turns hooks) is refused: 0.1.34 already
maps its numbers.
"""
import os
import re
import sys


def die(msg):
    sys.exit('cpstock: ' + msg)


if len(sys.argv) != 2:
    die('usage: cpstock.py <smali tree>')
root = sys.argv[1]
F = os.path.join(root, 'com/daudio/app/dipo/e/u.smali')
if not os.path.isfile(F):
    die('no com/daudio/app/dipo/e/u.smali in %s' % root)
if os.path.isdir(os.path.join(root, 'com/leafia')):
    die('com/leafia is there: a bridge build, its numbers are mapped by 0.1.34 (not for this step)')
for dp, _, names in os.walk(root):
    for n in names:
        if n.endswith('.smali'):
            with open(os.path.join(dp, n)) as f:
                if 'Lcom/jmk/hud/TurnsOut;' in f.read():
                    die('%s already has the Turns hooks' % os.path.relpath(os.path.join(dp, n), root))

LBL = r':[a-z_]+[0-9a-f]+'
PSW = r':pswitch_[0-9a-f]+'


def rx(lines):     # @L: a jump target, @P: a packed-switch case label line; blank lines between instructions are free
    return r'\s+'.join(re.escape(l).replace('@L', LBL).replace('@P', PSW) for l in lines)


C1 = 'const/4 v1, 0x1'
SIDE1 = [C1, 'if-ne v3, v1, @L', C1, 'if-ne v5, v1, @L']          # driving side 1, junction 1


def row(angle):
    if angle is None:
        return SIDE1 + ['if-nez v6, @L']
    return SIDE1 + ['const/16 v1, %s' % angle, 'if-ne v6, v1, @L']


# (name, lines before the constant, number now, stock number, lines after)
EDITS = [
    ('9 on-ramp 172 -> 160',
     ['const/16 v1, 0xac', 'goto/16 @L', '@P', 'if-nez v3, @L', 'if-nez v5, @L',
      'if-nez v6, @L'], 0xac, 0xa0),
    ('22 expressway exit left 82 -> 165',
     ['const/16 v1, 0x66', 'goto/16 @L', '@P', 'if-nez v3, @L', 'if-nez v5, @L', 'if-nez v6, @L'], 0x52, 0xa5),
    ('23 expressway exit right 81 -> 164',
     ['const/16 v1, 0x52', 'goto/16 @L', '@P', 'if-nez v3, @L', 'if-nez v5, @L', 'if-nez v6, @L'], 0x51, 0xa4),
    ('left-hand roundabout 0 degrees 97 -> 193', row(None), 0x61, 0xc1),
    ('left-hand roundabout 90 degrees 99 -> 195', row('0x5a'), 0x63, 0xc3),
    ('left-hand roundabout 120 degrees 100 -> 196', row('0x78'), 0x64, 0xc4),
    ('left-hand roundabout 180 degrees 102 -> 198', row('0xb4'), 0x66, 0xc6),
    ('left-hand roundabout -120 degrees 104 -> 200', row('-0x78'), 0x68, 0xc8),
    ('left-hand roundabout -90 degrees 105 -> 201', row('-0x5a'), 0x69, 0xc9),
    ('left-hand roundabout -30 degrees 107 -> 203', row('-0x1e'), 0x6b, 0xcb),
    ('type 31 enter roundabout, left-hand 96 -> 192', row(None), 0x60, 0xc0),
]

src = open(F).read()
HEAD = re.compile(r'^\.method [^\n]* a\(Ljava/lang/Integer;Ljava/lang/Object;\)V\n.*?^\.end method\n', re.S | re.M)
found = HEAD.findall(src)
if len(found) != 1:
    die('the table method u.a(Integer, Object) found %d times (want 1)' % len(found))
body = found[0]
spans = []      # (start, end, stock number, name) of each number, all found in the unmodified text
for name, before, now, stock in EDITS:
    pat = re.compile('(' + rx(before) + r'\s+const/16 v1, )(0x%x)(\s+goto/16 %s)' % (now, LBL))
    hits = list(pat.finditer(body))
    if len(hits) != 1:
        die('%s: found %d times (want 1)' % (name, len(hits)))
    spans.append((hits[0].start(2), hits[0].end(2), stock, name))
spans.sort()
for a, b in zip(spans, spans[1:]):
    if a[1] > b[0]:
        die('%s and %s overlap' % (a[3], b[3]))
for start, end, stock, name in reversed(spans):
    body = body[:start] + '0x%x' % stock + body[end:]
open(F, 'w').write(src.replace(found[0], body, 1))
print('cpstock: %d table numbers restored' % len(spans))
