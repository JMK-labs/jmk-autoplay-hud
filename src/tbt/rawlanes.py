#!/usr/bin/env python3
"""jmk-autoplay-hud 0.3.3 (AGPL-3.0, as this package). The CarPlay lane message arrives raw (libiap2session's recipe carplay-lanes-iap2): the lane frame is built from it.

    src/tbt/rawlanes.py <smali tree of an HKMC_DiPO bridge result that already holds com/jmk/hud/RawLanes and com/jmk/hud/Lanes>

In com/daudio/app/dipo/e/u:
  1. u.laneRaw(status, angles, highlights) is added: the tail of laneOne (the lane's status, the glyph ids of its first three angles, Lanes.record, LeafiaLane.cpLane; a null answer of cpLane, or any exception inside, gives the lane's own values)
     for values that were read from bytes.
  2. u.applyLanes: where the structured lane groups are missing (no param 2 of type group), RawLanes.decode(msg) reads the raw lane blobs; a result below 0 means "send nothing"
     (return); each decoded lane then goes through u.laneRaw into the same arrays the structured path fills.
Each place is found exactly once; otherwise nothing is written and the exit status is 1.
"""
import os
import re
import sys


def die(msg):
    sys.exit('rawlanes: ' + msg)


if len(sys.argv) != 2:
    die('usage: rawlanes.py <smali tree>')
root = sys.argv[1]
for need in ('RawLanes', 'Lanes'):
    if not os.path.isfile(os.path.join(root, 'com/jmk/hud/%s.smali' % need)):
        die('com/jmk/hud/%s.smali is not in the tree (rawlanes.sh adds RawLanes; Lanes comes with the 0.1.29 build)' % need)
U = os.path.join(root, 'com/daudio/app/dipo/e/u.smali')
if not os.path.isfile(U):
    die('com/daudio/app/dipo/e/u.smali is not in the tree: this step is for an HKMC_DiPO bridge build')
us = open(U).read()
if 'Lcom/jmk/hud/RawLanes;' in us or '.method public static laneRaw(' in us:
    die('already done')

APPLY = re.compile(r'^\.method public static applyLanes\(Ljava/lang/Object;\)V\n.*?^\.end method\n', re.S | re.M)
found = APPLY.findall(us)
if len(found) != 1:
    die('applyLanes found %d times (want 1)' % len(found))
body = found[0]
HOOK = ('    :cond_45\n    if-nez v6, :cond_49\n\n    const/4 v9, 0x0\n\n    goto :goto_70\n')
if body.count(HOOK) != 1:
    die('the place without lane groups was found %d times in applyLanes (want 1)' % body.count(HOOK))
NEW = ('    :cond_45\n    if-nez v6, :cond_49\n\n'
       '    invoke-static {p0}, Lcom/jmk/hud/RawLanes;->decode(Ljava/lang/Object;)I\n\n    move-result v2\n\n'
       '    if-gez v2, :cond_jmk_raw\n\n    return-void\n\n    :cond_jmk_raw\n'
       '    const/4 v3, 0x0\n\n    const/4 v9, 0x0\n\n'
       '    :goto_jmk_raw\n    if-ge v3, v2, :goto_70\n\n    const/16 v5, 0x8\n\n    if-ge v9, v5, :goto_70\n\n'
       '    invoke-static {v3}, Lcom/jmk/hud/RawLanes;->status(I)I\n\n    move-result v5\n\n'
       '    invoke-static {v3}, Lcom/jmk/hud/RawLanes;->angles(I)[I\n\n    move-result-object v7\n\n'
       '    invoke-static {v3}, Lcom/jmk/hud/RawLanes;->hl(I)[I\n\n    move-result-object v8\n\n'
       '    invoke-static {v5, v7, v8}, Lcom/daudio/app/dipo/e/u;->laneRaw(I[I[I)[I\n\n    move-result-object v4\n\n'
       '    const/4 v5, 0x0\n\n    aget v7, v4, v5\n\n    aput v7, v10, v9\n\n'
       '    const/4 v5, 0x1\n\n    aget v7, v4, v5\n\n    aput v7, v11, v9\n\n'
       '    const/4 v5, 0x2\n\n    aget v7, v4, v5\n\n    aput v7, v12, v9\n\n'
       '    const/4 v5, 0x3\n\n    aget v7, v4, v5\n\n    aput v7, v13, v9\n\n'
       '    add-int/lit8 v9, v9, 0x1\n\n    add-int/lit8 v3, v3, 0x1\n\n    goto :goto_jmk_raw\n')
us = us.replace(body, body.replace(HOOK, NEW, 1), 1)

LANE_RAW = '''
.method public static laneRaw(I[I[I)[I
    .registers 10

    const/4 v0, 0x4

    new-array v0, v0, [I

    const/4 v1, 0x1

    const/4 v2, 0x0

    aput v1, v0, v2

    :try_start_jmk
    const/4 v3, 0x2

    if-ne p0, v3, :cond_jmk_a

    aput v3, v0, v2

    :cond_jmk_a
    if-eqz p2, :cond_jmk_b

    array-length v1, p2

    if-lez v1, :cond_jmk_b

    aput v3, v0, v2

    :cond_jmk_b
    if-eqz p1, :cond_jmk_e

    array-length v1, p1

    const/4 v2, 0x0

    const/4 v4, 0x0

    :goto_jmk_c
    const/4 v5, 0x3

    if-ge v2, v1, :cond_jmk_e

    if-ge v4, v5, :cond_jmk_e

    aget v5, p1, v2

    invoke-static {v5}, Lcom/daudio/app/dipo/e/u;->laneIcon(I)I

    move-result v5

    if-eqz v5, :cond_jmk_d

    add-int/lit8 v6, v4, 0x1

    aput v5, v0, v6

    add-int/lit8 v4, v4, 0x1

    :cond_jmk_d
    add-int/lit8 v2, v2, 0x1

    goto :goto_jmk_c

    :cond_jmk_e
    invoke-static {p0, p1, p2}, Lcom/jmk/hud/Lanes;->record(I[I[I)V

    invoke-static {v0, p1, p2, p0}, Lcom/leafia/kr/LeafiaLane;->cpLane([I[I[II)[I

    move-result-object v1

    if-eqz v1, :cond_jmk_f

    return-object v1

    :cond_jmk_f
    return-object v0

    :try_end_jmk
    .catch Ljava/lang/Throwable; {:try_start_jmk .. :try_end_jmk} :catch_jmk

    :catch_jmk
    return-object v0
.end method
'''
if us.count('.end method\n') < 1:
    die('no method end found')
LANEONE = re.compile(r'^\.method private static laneOne\(Lcom/tcc/iap2/Iap2NotiMsg\$Iap2ObjGroup;\)\[I\n.*?^\.end method\n', re.S | re.M)
lo = LANEONE.findall(us)
if len(lo) != 1:
    die('laneOne found %d times (want 1)' % len(lo))
us = us.replace(lo[0], lo[0] + LANE_RAW, 1)
open(U, 'w').write(us)
print('rawlanes: applyLanes reads the raw lane blobs; u.laneRaw is added')
