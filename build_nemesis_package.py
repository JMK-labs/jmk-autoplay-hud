#!/usr/bin/env python3
"""jmk-autoplay-hud: a deterministic NEMESIS ZIP from package/ plus the licence files (AGPL-3.0, see LICENSE).

    python3 build_nemesis_package.py                  # dist/jmk-autoplay-hud-<v>.zip, every car set Leafia ships
    python3 build_nemesis_package.py --sets neev_kr   # dist/jmk-autoplay-hud-<v>-kr.zip, only those sets (small)

Test builds only: the output never goes to dist/release and is never published from here. Same inputs and the same
built date (JMK_BUILT_DATE=YYYY-MM-DD, default today) give the same bytes. Nothing is obfuscated: the zip is the source.
"""
import datetime
import hashlib
import os
import re
import sys
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent
PACKAGE = PROJECT / 'package'
TOP_FILES = ('LICENSE', 'NOTICE.md', 'README.md', 'src/jmkhud/CodeSum.java', 'src/build-codesum.sh', 'src/mkbycode.py',   # 0.1.3: tools/codesum.jar's source rides along
             # 0.1.11: the source of the GPM / DiPO near-turn change (our class and the hooks on Leafia's code)
             'src/tbt/com/jmk/hud/Near.java', 'src/tbt/near-hooks.diff', 'src/tbt/build.sh',
             # 0.1.13: the DiPO wireless iAP2 fix (applied by src/tbt/build.sh)
             'src/tbt/wireless-iap2.diff',
             # 0.1.17: the generator of patches/known (our own earlier results, for ours())
             'src/mkknown.py')
FIXED = (2026, 1, 1, 0, 0, 0)   # deterministic zip times
EXEC = ('.sh',)
EXEC_FILES = ('tools/lpatch',)


def field(text, key):
    m = re.search(r'^%s=(.*)$' % re.escape(key), text, re.M)
    return m.group(1).strip().strip('"') if m else ''


def built_stamp(data):
    """NEMESIS.data plus a '# built=YYYY-MM-DD' comment: the MAP menu's ABOUT screen shows it."""
    text = data.decode('utf-8')
    if '\n# built=' in text:
        return data
    day = os.environ.get('JMK_BUILT_DATE') or datetime.date.today().isoformat()
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', day):
        raise SystemExit('JMK_BUILT_DATE must be YYYY-MM-DD')
    return (text.rstrip('\n') + '\n# built=' + day + '\n').encode('utf-8')


def manifest_patches(text):
    """The patches of the files the car ends up with (scripts/common.sh load_targets): a 3_bridge line replaces the
    2_tbt line of the same file, so that 2_tbt patch is not shipped."""
    lines = [l.split() for l in text.splitlines()]
    lines = [w for w in lines if len(w) == 5 and w[0] in ('2_tbt', '3_bridge') and w[1] in ('app', 'file')]
    bridged = {w[2] for w in lines if w[0] == '3_bridge'}
    return [w[3] for w in lines if w[0] == '3_bridge' or w[2] not in bridged]


def main():
    args = sys.argv[1:]
    sets = None
    if '--sets' in args:
        i = args.index('--sets')
        sets = [s for s in args[i + 1].split(',') if s]
    data = (PACKAGE / 'NEMESIS.data').read_text(encoding='utf-8')
    version = field(data, 'package-version')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise SystemExit('NEMESIS.data: package-version %r' % version)
    if len(field(data, 'short-desc')) > 64 or len(field(data, 'detailed-desc')) > 256:   # NEMESIS META_DETAIL_MAX
        raise SystemExit('NEMESIS.data: short-desc must be <= 64 and detailed-desc <= 256 characters')
    for name in TOP_FILES:
        if not (PROJECT / name).is_file():
            raise SystemExit('missing ' + name)

    patches = PACKAGE / 'patches'
    all_sets = sorted(p.name for p in patches.iterdir() if p.is_dir() and (p / 'manifest').is_file())
    chosen = all_sets if sets is None else sets
    for s in chosen:
        if s not in all_sets:
            raise SystemExit('no patch set %s (have %s)' % (s, ', '.join(all_sets)))
    needed = set()
    for s in chosen:
        for rel in manifest_patches((patches / s / 'manifest').read_text()):
            if not (patches / rel).is_file():
                raise SystemExit('patches/%s/manifest names a missing patch %s' % (s, rel))
            needed.add('patches/' + rel)

    entries = {}
    for path in sorted(PACKAGE.rglob('*')):
        if not path.is_file() or path.name.startswith('.') or '__pycache__' in path.parts:
            continue
        rel = path.relative_to(PACKAGE).as_posix()
        if rel.startswith('patches/bycode/') and sets is not None:
            continue   # 0.1.4: the by-code profiles ride with the full build only (a --sets build is one car's test zip)
        if rel.startswith('patches/'):
            parts = rel.split('/')
            if len(parts) == 3:
                if parts[2].endswith('.lpd') and rel not in needed:
                    continue
                if parts[1] != 'common' and parts[1] not in chosen:
                    continue
        entries[rel] = path.read_bytes()
    if sets is not None:   # patches/cars: only the lines of the sets inside
        keep = []
        for line in entries['patches/cars'].decode('utf-8').splitlines():
            w = line.split()
            if not w or w[0].startswith('#') or (len(w) > 1 and w[1] in chosen):
                keep.append(line)
        entries['patches/cars'] = ('\n'.join(keep) + '\n').encode('utf-8')
    entries['NEMESIS.data'] = built_stamp(entries['NEMESIS.data'])
    for name in TOP_FILES:
        entries[name] = (PROJECT / name).read_bytes()
    for path in sorted((PROJECT / 'LICENSES').iterdir()):
        if path.is_file():
            entries['LICENSES/' + path.name] = path.read_bytes()

    suffix = '' if sets is None else '-' + ('kr' if chosen == ['neev_kr'] else '-'.join(chosen))
    out = PROJECT / 'dist' / ('jmk-autoplay-hud-%s%s.zip' % (version, suffix))
    if 'release' in out.parts:
        raise SystemExit('test builds never go to dist/release')
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED)
            info.external_attr = (0o755 if name.endswith(EXEC) or name in EXEC_FILES else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            z.writestr(info, entries[name])
    # 2026-11-19 (the owner): every zip we build, release or test, carries our file-integrity signature
    # (tools/release/sign_integrity.py: integrity.json + integrity.sig; the cars lock on files that do not match)
    sys.path.insert(0, str(PROJECT.parent.parent / 'tools' / 'release'))
    import sign_integrity
    sign_integrity.sign_zip(out)
    blob = out.read_bytes()
    print('%s  %d bytes  %d files  sets=%s' % (out, len(blob), len(entries), ','.join(chosen)))
    print('md5    ' + hashlib.md5(blob).hexdigest())
    print('sha256 ' + hashlib.sha256(blob).hexdigest())


if __name__ == '__main__':
    main()
