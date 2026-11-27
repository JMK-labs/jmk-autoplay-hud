#!/usr/bin/env python3
"""jmk-autoplay-hud 0.1.22 (AGPL-3.0, as this package): the CarPlay bridge's iPhone check (com/ev6/cpwl/Bridge.isApple)
goes to com/jmk/hud/Apple.java, which also looks at an iPhone whose Device ID vendor is not known yet (0).

    src/tbt/apple.py <smali tree>        (the DiPO tree with com/ev6/cpwl/Bridge.smali)

The method must be found exactly once; otherwise nothing is written and the exit status is 1. Apple.smali itself is
added by the caller (src/tbt/apple.sh).
"""
import os
import re
import sys

root = sys.argv[1]
rel = 'com/ev6/cpwl/Bridge.smali'
path = os.path.join(root, rel)
if not os.path.isfile(path):
    sys.exit('apple: no %s in %s' % (rel, root))
s = open(path).read()
pat = re.compile(r'^\.method static isApple\(Landroid/bluetooth/BluetoothDevice;\)Z\n.*?^\.end method\n', re.S | re.M)
found = pat.findall(s)
if len(found) != 1:
    sys.exit('apple: isApple found %d times (want 1)' % len(found))
new = ('.method static isApple(Landroid/bluetooth/BluetoothDevice;)Z\n'
       '    .registers 2\n\n'
       '    invoke-static {p0}, Lcom/jmk/hud/Apple;->is(Landroid/bluetooth/BluetoothDevice;)Z\n\n'
       '    move-result v0\n\n'
       '    return v0\n'
       '.end method\n')
s = pat.sub(lambda m: new, s, count=1)
with open(path, 'w') as f:
    f.write(s)
print('apple: Bridge.isApple -> com.jmk.hud.Apple.is')
