#!/usr/bin/env python3
"""Write package/patches/known (0.1.17): every result file a version of this add-on wrote that has one md5 on every car.
AGPL-3.0, as this package.

    src/mkknown.py            (from the repository root or anywhere inside it; needs git)
    src/mkknown.py --check    (test/check-scripts.sh: exit 1 when package/patches/known is not what this gives)

ours() (scripts/common.sh) counts a live file as this package's when the applied record names it. A car whose record does
not (GMI6OZC2, Ioniq 5 Korea, 2026-11-20: HKMC_GPM.apk 1c4bfdda, the neev_kr GPM build of 0.1.0-0.1.4, with no line for
it) was locked as if another tool had written the file, on every later version. This list lets ours() tell our own
earlier builds apart from a foreign file. Sources, all versions:
  - every committed version of package/patches/<set>/manifest (the fixed sets): an app line's md5 is the rebuilt .apk
    (the set's own stock apk + the result dex), a file line's the rebuilt library; a 2_tbt line that a 3_bridge line of
    the same file replaces is left out (this package installs the bridge build directly);
  - every committed version of package/patches/bycode/<profile>/manifest: only the file (library) lines, whose md5 is
    the library itself (an app line's md5 is the result dex; the .apk around it is made from each car's own stock apk);
  - the manifests inside every zip in dist/release (what was published) and dist/ (test builds installed over adb).
An .odex is never listed: our dexopt writes it, so it is ours when its apk is (ours()). Lines: "<file> <md5>", sorted.
"""
import io
import os
import re
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
OUT = os.path.join(APP, 'package', 'patches', 'known')
MD5 = re.compile(r'^[0-9a-f]{32}$')


def lines_of(text, bycode, found):
    rows = [l.split() for l in text.splitlines()]
    rows = [w for w in rows if w and not w[0].startswith('#')]
    # a 3_bridge line replaces the 2_tbt line of the same file: this package writes the bridge build directly, never
    # that 2_tbt build (Leafia installs it first, then the bridge over it), so it is not one of ours
    bridged = {w[2] for w in rows if w[0] == '3_bridge'}
    for w in rows:
        if w[0] == '2_tbt' and w[2] in bridged:
            continue
        if bycode:          # <part> <kind> <name> <code> <patch> <want>
            if len(w) >= 6 and w[1] == 'file' and MD5.match(w[5]):
                found.add((w[2], w[5]))
        else:               # <part> <kind> <name> <patch> <want>
            if len(w) >= 5 and MD5.match(w[4]) and w[4] != '0' * 32:
                found.add((w[2] + '.apk' if w[1] == 'app' else w[2], w[4]))


def git(*a):
    return subprocess.run(['git', '-C', APP] + list(a), check=True, capture_output=True).stdout.decode('utf-8', 'replace')


def main():
    found = set()
    paths = [p for p in git('log', '--all', '--format=', '--name-only', '--', 'package/patches').split('\n')
             if p.endswith('/manifest')]
    top = git('rev-parse', '--show-toplevel').strip()
    rel = os.path.relpath(APP, top)
    for p in sorted(set(paths)):
        bycode = '/bycode/' in p
        for c in git('log', '--all', '--format=%H', '--', p).split():
            try:
                text = git('show', '%s:%s' % (c, p))
            except subprocess.CalledProcessError:
                continue        # deleted in that commit
            lines_of(text, bycode, found)
    for p in os.listdir(os.path.join(APP, 'package', 'patches')):   # the working tree too (this version)
        m = os.path.join(APP, 'package', 'patches', p, 'manifest')
        if os.path.isfile(m):
            lines_of(open(m).read(), False, found)
    bc = os.path.join(APP, 'package', 'patches', 'bycode')
    for p in os.listdir(bc):
        m = os.path.join(bc, p, 'manifest')
        if os.path.isfile(m):
            lines_of(open(m).read(), True, found)
    zips = 0
    for d in ('dist/release', 'dist'):
        dd = os.path.join(APP, d)
        for z in sorted(os.listdir(dd)) if os.path.isdir(dd) else []:
            if not z.endswith('.zip'):
                continue
            zips += 1
            with zipfile.ZipFile(os.path.join(dd, z)) as zf:
                for n in zf.namelist():
                    if n.endswith('/manifest') and '/patches/' in '/' + n:
                        lines_of(zf.read(n).decode('utf-8', 'replace'), '/bycode/' in n, found)
    text = ('# results of this add-on (src/mkknown.py, %s): "<file> <md5>" of every rebuilt .apk of a fixed set and every\n' % rel
            + '# rebuilt library any version wrote; ours() counts a live file with one of these md5s as this package\'s.\n'
            + ''.join('%s %s\n' % (name, s) for name, s in sorted(found)))
    if '--check' in sys.argv[1:]:
        have = open(OUT).read() if os.path.isfile(OUT) else ''
        print('%s: %s (%d results)' % (OUT, 'up to date' if have == text else 'NOT what src/mkknown.py gives', len(found)))
        return 0 if have == text else 1
    with open(OUT, 'w') as f:
        f.write(text)
    print('%d results (%d manifest paths in git, %d zips) -> %s' % (len(found), len(set(paths)), zips, OUT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
