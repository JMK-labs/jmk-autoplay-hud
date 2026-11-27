#!/usr/bin/env python3
"""jmk-autoplay-hud (AGPL-3.0, as this package).

    src/tbt/callout.py <smali tree of a DiPO bridge result that already holds com/jmk/hud/Callout>

HUD DiPO bridge: at the point where Leafia starts the car hotspot it asks a local JMK service (`jmk.core`) first and skips its own
start when the service answers that it should (the hotspot is already on or being started, or the car's settings keep it off) —
readable in the public HUD source.
"""
import os
import re
import sys


def die(msg):
    sys.exit('callout: ' + msg)


if len(sys.argv) != 2:
    die('usage: callout.py <smali tree>')
root = sys.argv[1]
F = os.path.join(root, 'com/ev6/cpwl/Bridge.smali')
if not os.path.isfile(F):
    die('no com/ev6/cpwl/Bridge.smali in %s' % root)
if not os.path.isfile(os.path.join(root, 'com/jmk/hud/Callout.smali')):
    die('com/jmk/hud/Callout.smali is not in the tree (callout.sh adds it first)')

src = open(F).read()
if 'jmkFresh' in src or 'Lcom/jmk/hud/Callout;' in src:
    die('Bridge.smali already has the call-out')

ANCHOR = '''    :cond_5c
    :try_start_5c
    const-string v1, "getWifiApConfiguration"
'''
HEAD = re.compile(r'^\.method static ensureHotspot\(Landroid/content/Context;\)V\n.*?^\.end method\n', re.S | re.M)
found = HEAD.findall(src)
if len(found) != 1:
    die('Bridge.ensureHotspot found %d times (want 1)' % len(found))
body = found[0]
if body.count(ANCHOR) != 1:
    die('the call site of Leafia\'s own start found %d times (want 1)' % body.count(ANCHOR))
if body.count('invoke-virtual {v4, v3, v5}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;') != 1 \
        or 'const-string v5, "setWifiApEnabledForConnectivity"' not in body:
    die('the stock call is not the one this step was written for')

CALL = '''    :cond_5c
    const/4 v1, 0x0

    :try_start_jmk
    invoke-static {}, Lcom/jmk/hud/Callout;->ask()I

    move-result v1
    :try_end_jmk
    .catchall {:try_start_jmk .. :try_end_jmk} :catch_jmk

    :goto_jmk
    const/4 v5, 0x1

    if-ne v1, v5, :cond_jmk

    goto/16 :goto_11

    :cond_jmk
    invoke-static {v3, v1}, Lcom/ev6/cpwl/Bridge;->jmkFresh(Ljava/lang/Object;I)I

    move-result v1

    if-eqz v1, :cond_go

    goto/16 :goto_11

    :catch_jmk
    move-exception v1

    const/4 v1, 0x0

    goto :goto_jmk

    :cond_go
    :try_start_5c
    const-string v1, "getWifiApConfiguration"
'''

FRESH = '''
.method static jmkFresh(Ljava/lang/Object;I)I
    .registers 9

    const/4 v0, 0x1

    const/4 v1, 0x2

    const/4 v2, 0x0

    :try_start_3
    invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;

    move-result-object v3

    const-string v4, "isWifiApEnabled"

    const/4 v5, 0x0

    invoke-virtual {v3, v4, v5}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;

    move-result-object v4

    invoke-virtual {v4, p0, v5}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;

    move-result-object v4

    check-cast v4, Ljava/lang/Boolean;

    invoke-virtual {v4}, Ljava/lang/Boolean;->booleanValue()Z

    move-result v4

    const-string v6, "getWifiApMode"

    invoke-virtual {v3, v6, v5}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;

    move-result-object v6

    invoke-virtual {v6, p0, v5}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;

    move-result-object v6

    check-cast v6, Ljava/lang/Integer;

    invoke-virtual {v6}, Ljava/lang/Integer;->intValue()I

    move-result v6

    if-eqz v4, :cond_2e

    if-ne v6, v1, :cond_2e

    const/4 v2, 0x1

    goto :goto_47

    :cond_2e
    if-ne p1, v1, :cond_47

    const-string p1, "getWifiApEnabledState"

    invoke-virtual {v3, p1, v5}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;

    move-result-object p1

    invoke-virtual {p1, p0, v5}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;

    move-result-object p0

    check-cast p0, Ljava/lang/Integer;

    invoke-virtual {p0}, Ljava/lang/Integer;->intValue()I

    move-result p0
    :try_end_40
    .catchall {:try_start_3 .. :try_end_40} :catchall_46

    const/16 p1, 0xc

    if-ne p0, p1, :cond_47

    const/4 v2, 0x2

    goto :goto_47

    :catchall_46
    nop

    :cond_47
    :goto_47
    const-string p0, "JMKHUD"

    if-ne v2, v0, :cond_51

    const-string p1, "Hotspot call: on via=direct hc=- caller=hud-dipo reason=bridge-spp aid=- hold=1 why=up"

    invoke-static {p0, p1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_5e

    :cond_51
    if-ne v2, v1, :cond_59

    const-string p1, "Hotspot call: on via=direct hc=- caller=hud-dipo reason=bridge-spp aid=- hold=1 why=starting"

    invoke-static {p0, p1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_5e

    :cond_59
    const-string p1, "Hotspot call: on via=direct hc=- caller=hud-dipo reason=bridge-spp aid=- hold=0"

    invoke-static {p0, p1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :goto_5e
    return v2
.end method
'''

new_body = body.replace(ANCHOR, CALL, 1)
# the new method goes right after ensureHotspot
out = src.replace(body, new_body + FRESH, 1)
open(F, 'w').write(out)
print('callout: Bridge.ensureHotspot asks Callout first; Bridge.jmkFresh added')
