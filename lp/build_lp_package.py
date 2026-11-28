#!/usr/bin/env python3
"""jmk-autoplay-hud, NEMESIS 1.17 LivePatch build: a deterministic signed ZIP from lp/package/ plus the Korean by-code profiles of ../package/ (AGPL-3.0, see LICENSE).

    python3 lp/build_lp_package.py            # dist/test/jmk-autoplay-hud-<v>-lp.zip   (a test build)
    python3 lp/build_lp_package.py --release  # dist/release/jmk-autoplay-hud-<v>.zip, the same bytes (release.sh)

A test build never goes to dist/release and is never published from here; the release form is what release.sh makes. Same inputs and the same built date
(JMK_BUILT_DATE=YYYY-MM-DD, default today) give the same bytes. Nothing is obfuscated: the zip is the source.
Ships: the Korean profiles (kr*) with only the patches their manifests name, the four CarPlay library recipes (the lane recipe for libiap2session.so, gated on one md5; no converter recipe, no libev6aac.so),
tools/hud-step + lpatch, the legacy restore, the sources the legacy zip carries. NEMESIS.data's [patch.N] sections and migrate.meta are written here.
"""
import hashlib, os, re, sys, zipfile
from pathlib import Path

LP = Path(__file__).resolve().parent
PROJECT = LP.parent
sys.path.insert(0, str(PROJECT))
import build_nemesis_package as legacy      # TOP_FILES (the source files that ride along), built_stamp, field

PKG = LP / 'package'
OLD = PROJECT / 'package'
FIXED = (2026, 1, 1, 0, 0, 0)
STOP = {'HKMC_GPM': 'com.google.android.projection.sink', 'HKMC_DiPO': 'com.daudio.app.dipo', 'Iap2ServerApp': 'com.tcc.iap2server',
        'HKMC_Navi_ExSL': 'com.mnsoft.navi', 'PhoneProjection': 'com.daudio.app.phoneprojection'}
RECIPES = ('carplay-audio-formats', 'carplay-core-frames-ef49c09b', 'carplay-core-wifi', 'carplay-lanes-iap2')   # not carplay-utils-converter: libev6aac.so is not shipped
LP_VERSION = '0.3.3'    # this build's version
LEGACY_BELOW = '0.3.1'  # the first LivePatch HUD version: an installed HUD below it is the legacy one (migrate.meta legacy_below)
VERSION_RE = re.compile(r'^\d+\.\d+\.\d+$')


def profiles():
    """Every Korean by-code profile (kr*): name -> list of manifest rows [part, kind, name, code md5, patch, result md5]."""
    out = {}
    for d in sorted((OLD / 'patches' / 'bycode').iterdir()):
        if d.is_dir() and d.name.startswith('kr') and (d / 'manifest').is_file():
            rows = []
            for line in (d / 'manifest').read_text().splitlines():
                w = line.split()
                if len(w) == 6 and w[0] in ('2_tbt', '3_bridge') and w[1] in ('app', 'file'):
                    rows.append(w)
            out[d.name] = rows
    return out


def recipe_lib(rid):
    for line in (OLD / 'recipes' / (rid + '.recipe')).read_text().splitlines():
        w = line.split()
        if w and w[0] == 'file':
            return w[1].rsplit('/', 1)[1]
    raise SystemExit('recipe %s names no file' % rid)


def sections(profs):
    apps, libs = [], []
    for rows in profs.values():
        for w in rows:
            lst = apps if w[1] == 'app' else libs
            if w[2] not in lst:
                lst.append(w[2])
    rlibs = []
    for rid in RECIPES:
        lib = recipe_lib(rid)
        if lib not in rlibs:
            rlibs.append(lib)
    text, n = [], 0

    def add(target, args, stop=None):
        nonlocal n
        n += 1
        text.append('[patch.%d]\ntarget=%s\nengine=exec\ntool=tools/hud-step\nargs=%s\n%soptional=1\n' % (n, target, args, ('stop=%s\n' % stop) if stop else ''))
    for a in apps:
        add('/system/app/%s.odex' % a, 'odex %s' % a, STOP.get(a))
    for l in libs:
        add('/system/lib/%s' % l, 'lib %s' % l)
    for l in rlibs:
        add('/system/lib/%s' % l, 'recipes %s' % l)
    return '\n'.join(text), apps, libs, rlibs


def main():
    data = (PKG / 'NEMESIS.data.in').read_text(encoding='utf-8')
    ver = os.environ.get('JMK_LP_VERSION', LP_VERSION)
    if not VERSION_RE.match(ver):
        raise SystemExit('version %r' % ver)
    profs = profiles()
    if not profs:
        raise SystemExit('no Korean by-code profile')
    sect, apps, libs, rlibs = sections(profs)
    entries = {}
    for path in sorted(PKG.rglob('*')):
        if not path.is_file() or path.name.startswith('.') or '__pycache__' in path.parts or path.name.endswith('.in'):
            continue
        entries[path.relative_to(PKG).as_posix()] = path.read_bytes()
    nem = data.replace('@VERSION@', ver).rstrip('\n') + '\n\n' + sect
    if len(legacy.field(nem, 'short-desc')) > 64 or len(legacy.field(nem, 'detailed-desc')) > 256:
        raise SystemExit('short-desc must be <= 64 and detailed-desc <= 256 characters')
    entries['NEMESIS.data'] = legacy.built_stamp(nem.encode('utf-8'))
    entries['migrate.meta'] = (PKG / 'migrate.meta.in').read_text().replace('@VERSION@', ver).replace('@LEGACY_BELOW@', LEGACY_BELOW).encode('utf-8')
    # the Korean profiles: manifest + knobs, and only the patches the manifests name (paths are relative to patches/)
    need = set()
    for name, rows in profs.items():
        for f in ('manifest', 'knobs'):
            p = OLD / 'patches' / 'bycode' / name / f
            if p.is_file():
                entries['tools/patches/bycode/%s/%s' % (name, f)] = p.read_bytes()
        for w in rows:
            need.add(w[4])
    for rel in sorted(need):
        p = OLD / 'patches' / rel
        if not p.is_file():
            raise SystemExit('a manifest names a missing patch: %s' % rel)
        entries['tools/patches/' + rel] = p.read_bytes()
    jar = OLD / 'tools' / 'codesum.jar'     # the legacy HUD's code reader (src/build-codesum.sh builds it); the ARM lpatch has no odexdex
    if not jar.is_file():
        raise SystemExit('package/tools/codesum.jar is missing: run src/build-codesum.sh')
    entries['tools/codesum.jar'] = jar.read_bytes()
    for rid in RECIPES:
        entries['tools/recipes/%s.recipe' % rid] = (OLD / 'recipes' / (rid + '.recipe')).read_bytes()
    gates = [l for l in (OLD / 'recipes' / 'gates').read_text().splitlines() if l.startswith('#') or l.split()[:1] and l.split()[0] in RECIPES]
    entries['tools/recipes/gates'] = ('\n'.join(gates) + '\n').encode('utf-8')
    for name in legacy.TOP_FILES:
        if not (PROJECT / name).is_file():
            raise SystemExit('missing ' + name)
        entries[name] = (PROJECT / name).read_bytes()
    for path in sorted((PROJECT / 'LICENSES').iterdir()):
        if path.is_file():
            entries['LICENSES/' + path.name] = path.read_bytes()
    out = PROJECT / 'dist' / 'release' / ('jmk-autoplay-hud-%s.zip' % ver) if '--release' in sys.argv[1:] else PROJECT / 'dist' / 'test' / ('jmk-autoplay-hud-%s-lp.zip' % ver)
    out.parent.mkdir(parents=True, exist_ok=True)
    execs = ('tools/hud-step', 'tools/lpatch')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED)
            info.external_attr = (0o755 if name.endswith('.sh') or name in execs else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            z.writestr(info, entries[name])
    sys.path.insert(0, str(PROJECT.parent.parent / 'tools' / 'release'))
    import sign_integrity
    sign_integrity.sign_zip(out)
    blob = out.read_bytes()
    print('%s  %d bytes  %d files  profiles=%s  targets=%d' % (out, len(blob), len(entries), ','.join(profs), len(apps) + len(libs) + len(rlibs)))
    print('md5    ' + hashlib.md5(blob).hexdigest())
    print('sha256 ' + hashlib.sha256(blob).hexdigest())


if __name__ == '__main__':
    main()
