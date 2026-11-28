#!/usr/bin/env bash
# Release build of the HUD (NEMESIS 1.17 LivePatch): the signed-later zip, nothing obfuscated (AGPL-3.0, the zip is the source) -> dist/release/jmk-autoplay-hud-<v>.zip
#   bash apps/jmk-autoplay-hud/release.sh        (JMK_BUILT_DATE=YYYY-MM-DD for a fixed built date; default today)
# The same bytes as the test build of the same inputs and date (lp/build_lp_package.py), under the release name. The lp-ci gate (tools/release/lp-ci.sh) judges this zip.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$dir/lp/build_lp_package.py" --release
