#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.29 (AGPL-3.0, as this package): the CarPlay lane frame of the DiPO bridge build gets the lane values
of com/jmk/hud/Lanes.java (the reference lane rule: component glyphs for a multi-direction lane, white / blue / grey by the
phone's LaneStatus and highlight).

    src/tbt/lanes.py <smali tree>        (the DiPO tree with com/leafia/kr/LeafiaLane.smali and com/daudio/app/dipo/e/u.smali)

Three hooks, all in com/daudio/app/dipo/e/u.smali, nothing else of the build is edited (not LeafiaLane.encodeCp, not
LeafiaPhoneFrame, whose lane() the non-CarPlay navigation source also uses):
  1. u.applyLanes (the lane builder, called once per 0x5204): Lanes.begin() at the start;
  2. u.laneOne (one lane group): Lanes.record(status, angles, highlight) with the raw LaneStatus, LaneAngles and
     LaneAngleHighlight arrays it already holds, just before it hands them to LeafiaLane.cpLane;
  3. u.applyLanes again: Lanes.patch(frame) after LeafiaLane.cp has rewritten the 81-byte 0xF1 frame and before cpGate and
     updateLaneInfo.
Each place must be found exactly once (and Lanes not be there yet); otherwise nothing is written and the exit status is 1.
Lanes.smali itself is added by the caller (src/tbt/lanes.sh).
"""
import os
import re
import sys


def die(msg):
    sys.exit('lanes: ' + msg)


root = sys.argv[1]
lane_rel = 'com/leafia/kr/LeafiaLane.smali'
u_rel = 'com/daudio/app/dipo/e/u.smali'
for rel in (lane_rel, u_rel):
    if not os.path.isfile(os.path.join(root, rel)):
        die('no %s in %s' % (rel, root))
lane_s = open(os.path.join(root, lane_rel)).read()
if not lane_s.startswith('.class public final Lcom/leafia/kr/LeafiaLane;\n'):
    die('LeafiaLane class not found')
cap = '.method public static declared-synchronized capture(Ljava/lang/String;Ljava/lang/String;I[B[BLjava/lang/String;)V\n'
if lane_s.count(cap) != 1:
    die('LeafiaLane.capture (the lane log) found %d times (want 1)' % lane_s.count(cap))

s = open(os.path.join(root, u_rel)).read()
if 'Lcom/jmk/hud/Lanes;' in s:
    die('%s already has the Lanes hooks' % u_rel)


def method(text, header):
    pat = re.compile(r'^' + re.escape(header) + r'\n.*?^\.end method\n', re.S | re.M)
    found = pat.findall(text)
    if len(found) != 1:
        die('%s found %d times (want 1)' % (header, len(found)))
    return found[0]


def replace_once(body, old, new, what):
    if body.count(old) != 1:
        die('%s found %d times (want 1)' % (what, body.count(old)))
    return body.replace(old, new, 1)


def regs(body):
    m = re.search(r'^    \.registers (\d+)\n', body, re.M)
    if not m:
        die('no .registers line')
    return int(m.group(1))


# ---- u.applyLanes: begin() first, patch(frame) after LeafiaLane.cp
h_apply = '.method public static applyLanes(Ljava/lang/Object;)V'
apply_old = method(s, h_apply)
apply_new = replace_once(apply_old, '    .registers 16\n\n',
                         '    .registers 16\n\n    invoke-static {}, Lcom/jmk/hud/Lanes;->begin()V\n\n', 'applyLanes .registers 16')
cp_call = '    invoke-static {v2, v10, v11, v12, v13}, Lcom/leafia/kr/LeafiaLane;->cp([B[I[I[I[I)V\n\n'
gate = '    invoke-static {v0, v2}, Lcom/leafia/kr/LeafiaLane;->cpGate(Ljava/lang/Object;[B)[B\n'
apply_new = replace_once(apply_new, cp_call + gate,
                         cp_call + '    invoke-static {v2}, Lcom/jmk/hud/Lanes;->patch([B)V\n\n' + gate,
                         'LeafiaLane.cp followed by cpGate in applyLanes')

# ---- u.laneOne: record(status, angles, highlight) before LeafiaLane.cpLane
h_one = '.method private static laneOne(Lcom/tcc/iap2/Iap2NotiMsg$Iap2ObjGroup;)[I'
one_old = method(s, h_one)
if regs(one_old) < 8:
    die('laneOne has too few registers (v5 v6 v7 needed)')
cp_lane = '    invoke-static {v0, v6, v7, v5}, Lcom/leafia/kr/LeafiaLane;->cpLane([I[I[II)[I\n'
one_new = replace_once(one_old, cp_lane, '    invoke-static {v5, v6, v7}, Lcom/jmk/hud/Lanes;->record(I[I[I)V\n\n' + cp_lane,
                       'LeafiaLane.cpLane call in laneOne')

s = s.replace(apply_old, apply_new, 1).replace(one_old, one_new, 1)
with open(os.path.join(root, u_rel), 'w') as f:
    f.write(s)
print('lanes: u.applyLanes begin + patch, u.laneOne record -> com.jmk.hud.Lanes')
