#!/usr/bin/env bash
# Builds package/tools/codesum.jar from src/jmkhud/CodeSum.java (0.1.3): javac (Java 7 class files) and the Android SDK's
# d8 (--min-api 19), then a jar holding only classes.dex with a fixed timestamp, so the same source gives the same bytes.
#   src/build-codesum.sh          (needs a JDK, and ANDROID_HOME or ~/Library/Android/sdk with platforms/android-19 and
#                                  build-tools/35.0.0)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
platform=$sdk/platforms/android-19/android.jar
d8=$sdk/build-tools/35.0.0/d8
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
javac -source 7 -target 7 -Xlint:-options -bootclasspath "$platform" -d "$work/classes" "$here/jmkhud/CodeSum.java"
(cd "$work/classes" && jar cf "$work/classes.jar" jmkhud)
"$d8" --min-api 19 --release --lib "$platform" --output "$work" "$work/classes.jar"
python3 - "$work/classes.dex" "$here/../package/tools/codesum.jar" <<'EOF'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_STORED) as z:
    info = zipfile.ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0))
    info.external_attr = 0o644 << 16
    info.create_system = 3
    z.writestr(info, open(src, 'rb').read())
EOF
shasum -a 256 "$here/../package/tools/codesum.jar"
