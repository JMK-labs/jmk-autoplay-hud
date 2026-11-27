#!/usr/bin/env python3
"""Make a by-code profile (0.1.4) from a car's patch set and that car's stock files. AGPL-3.0, as this package.

    src/mkbycode.py <set> <profile> <stock dir>...      e.g.  src/mkbycode.py neev_kr kr <dir of the car's stock files> <dir of its app stock files>

A patch set rebuilds each app's modified code from one car's exact stock .odex. An .odex is the app's dex plus a header
that carries its framework's checksums, so another car whose app runs the same code has the same dex inside a different
.odex. This writes package/patches/bycode/<profile>/:

    manifest   <part> app <App> <md5 of the dex inside the stock .odex> bycode/<profile>/<App>.<part>.lpd <md5 of the result dex>
               <part> file <library> <md5 of the stock library> <the set's own .lpd> <md5 of the result>
    knobs      the set's knobs (the same builds read the same keys)
    *.lpd      lpatch deltas from that dex to the set's result dex (the format of Leafia's lpatch: LPD1, bsdiff, raw deflate)

The result dex is the set's own (rebuilt here from the stock .odex with the set's .lpd and checked against the .lpd's md5),
so a car with the same code gets byte for byte the code the set's car gets. Needs bsdiff4 (gen5w-Evergreen's
tools/requirements.txt, pinned by hash). The stock files never go into the package: only the deltas and md5s.
"""
import hashlib
import os
import struct
import sys
import zlib

import bsdiff4.core

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'package', 'patches')


def md5(b):
    return hashlib.md5(b).hexdigest()


def lpd_apply(src, lpd):
    """lpatch delta, in Python: rebuild the target from src (checks both md5s, as lpatch does)."""
    if lpd[:4] != b'LPD1':
        raise SystemExit('not an LPD1 delta')
    slen, = struct.unpack_from('<I', lpd, 4)
    smd5 = lpd[8:24]
    tlen, = struct.unpack_from('<I', lpd, 24)
    tmd5 = lpd[28:44]
    comp, plen = struct.unpack_from('<II', lpd, 44)
    if comp != 1 or len(src) != slen or hashlib.md5(src).digest() != smd5:
        raise SystemExit('the source is not the one this delta needs')
    body = zlib.decompressobj(-15).decompress(lpd[52:52 + plen])
    n, = struct.unpack_from('<I', body, 0)
    p = 4
    ctrl = []
    for _ in range(n):
        ctrl.append(struct.unpack_from('<iii', body, p))
        p += 12
    dlen, = struct.unpack_from('<I', body, p); p += 4
    diff = body[p:p + dlen]; p += dlen
    elen, = struct.unpack_from('<I', body, p); p += 4
    extra = body[p:p + elen]
    out = bytearray()
    op = dp = ep = 0
    for x, y, z in ctrl:
        out += bytes((src[op + i] + diff[dp + i]) & 255 for i in range(x)) if x else b''
        dp += x
        op += x
        out += extra[ep:ep + y]
        ep += y
        op += z
    out = bytes(out)
    if len(out) != tlen or hashlib.md5(out).digest() != tmd5:
        raise SystemExit('the rebuilt target does not match the delta')
    return out


def lpd_make(a, b):
    """gen5w-Evergreen's mkdelta.py format: what lpatch delta reads."""
    ctrl, diff, extra = bsdiff4.core.diff(a, b)
    body = struct.pack('<I', len(ctrl))
    for x, y, z in ctrl:
        body += struct.pack('<iii', x, y, z)
    body += struct.pack('<I', len(diff)) + diff + struct.pack('<I', len(extra)) + extra
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    payload = c.compress(body) + c.flush()
    hdr = (b'LPD1' + struct.pack('<I', len(a)) + hashlib.md5(a).digest() + struct.pack('<I', len(b))
           + hashlib.md5(b).digest() + struct.pack('<II', 1, len(payload)))
    d = hdr + payload
    if lpd_apply(a, d) != b:
        raise SystemExit('self-check failed')
    return d


def odex_dex(o):
    if o[:4] != b'dey\n':
        raise SystemExit('not a Dalvik odex')
    off, ln = struct.unpack_from('<II', o, 8)
    d = o[off:off + ln]
    if d[:4] != b'dex\n':
        raise SystemExit('no dex inside')
    return d


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    sset, profile, dirs = sys.argv[1], sys.argv[2], sys.argv[3:]
    sdir = os.path.join(PATCHES, sset)
    stock = dict(l.split() for l in open(os.path.join(sdir, 'stock')) if l.strip() and not l.startswith('#'))
    files = {}
    for d in dirs:
        for root, _, names in os.walk(d):
            for n in names:
                p = os.path.join(root, n)
                if n in stock and md5(open(p, 'rb').read()) == stock[n]:
                    files.setdefault(n, p)
    out = os.path.join(PATCHES, 'bycode', profile)
    os.makedirs(out, exist_ok=True)
    lines = ['# by-code profile %s (src/mkbycode.py): made from the %s set and that car\'s own stock files.' % (profile, sset),
             '# <part> app <App> <md5 of the dex inside the stock .odex> <patch> <md5 of the result dex>',
             '# <part> file <library> <md5 of the stock library> <patch> <md5 of the result>']
    for l in open(os.path.join(sdir, 'manifest')):
        w = l.split()
        if len(w) < 5 or w[0].startswith('#'):
            continue
        part, kind, name, patch, want = w[:5]
        lpd = open(os.path.join(PATCHES, patch), 'rb').read()
        if kind == 'app':
            if name + '.odex' not in files:
                raise SystemExit('%s.odex (md5 %s) is not in the stock dirs' % (name, stock.get(name + '.odex')))
            o = open(files[name + '.odex'], 'rb').read()
            result = lpd_apply(o, lpd)          # the set's own rebuilt code (classes.dex)
            code = odex_dex(o)
            fn = '%s.%s.lpd' % (name, part.split('_', 1)[1])
            open(os.path.join(out, fn), 'wb').write(lpd_make(code, result))
            lines.append('%s app %s %s bycode/%s/%s %s' % (part, name, md5(code), profile, fn, md5(result)))
            print('%-8s %-16s code %s -> dex %s' % (part, name, md5(code)[:8], md5(result)[:8]))
        else:
            if stock.get(name) is None:
                raise SystemExit('no stock md5 for ' + name)
            lines.append('%s file %s %s %s %s' % (part, name, stock[name], patch, want))
            print('%-8s %-16s file %s -> %s (the set\'s own delta)' % (part, name, stock[name][:8], want[:8]))
    open(os.path.join(out, 'manifest'), 'w').write('\n'.join(lines) + '\n')
    k = os.path.join(sdir, 'knobs')
    if os.path.exists(k):
        open(os.path.join(out, 'knobs'), 'w').write(open(k).read())
    print('wrote', out)


if __name__ == '__main__':
    main()
