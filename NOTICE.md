# NOTICE: jmk-autoplay-hud ("JMK AutoPlay 확장 (HUD · 계기판 길안내)")

This package is free software under the **GNU Affero General Public License version 3** (`LICENSE`). It is a fork of
the parts named below; their licence notices are kept (`LICENSES/`). It comes with no warranty.

Source: https://github.com/JongMinKim-93/jmk-autoplay-hud (the zip itself is the complete source of the scripts; the
patch data is data; the binaries are listed below with their sources).

## Upstream

- **NEMESIS** by xwtk (https://github.com/xwtk/hmg_nemesis), AGPL-3.0: the package manager these hooks run under.
- **Turn-by-Turn Guidance for Phone Projection** (`projection.tbt`), a NEMESIS community package, AGPL-3.0, as shipped
  inside HMG Leafia Plus 1.0.5 (`comp/2_tbt`). Its install logic is the base of `package/scripts/common.sh` (snapshot,
  copy beside and rename, odex rewrite with dexopt, dalvik-cache fill and wipe, restore) and `package/bin/status.sh`;
  its app builds are the base of the turn-by-turn and bridge patch data.
- **HMG Leafia Plus 1.0.5** (original package id `wireless.carplay.aa`), GPL-3.0 (`LICENSES/GPL-3.0.txt`,
  `LICENSES/UPSTREAM_NOTICE-leafia-plus.md`). Its source, including `lpatch`, the CarPlay bridge and the recipe
  tooling: https://github.com/VysseCodes/HMG-Leafia-Plus (archived; community fork https://github.com/zpoon/HMG-Leafia-Plus):
  - `package/tools/lpatch` (unmodified ARM binary, sha256 b11077ab6bbba7a2dbed225340d06db46c843a667a3813f894f2927ec61c2bb6,
    the same as in the original 1.0.5 zip);
  - the patch data layout and the per-car patch sets `package/patches/` (cars, `<set>/stock`, `<set>/manifest`,
    `*.tbt.lpd`, `*.bridge.lpd`);
  - the CarPlay Bluetooth bridge (part `3_bridge`, `wireless.carplay.bt`): the bridge builds of HKMC_DiPO,
    Iap2ServerApp and PhoneProjection, and `recipes/carplay-core-wifi.recipe`;
  - the CarPlay Wi-Fi audio (part `4_audio`, `carplay.wifi.audio`): `recipes/carplay-audio-formats.recipe`,
    `recipes/carplay-utils-converter.recipe` and `package/files/libev6aac.so` (unmodified, md5
    badc26bd4c40a1c3e543b733a8ec5028);
  - script logic from `scripts/cars.sh`, `scripts/build.sh`, `scripts/lpatch.sh` and `apps_hold` / `apps_release` of
    `scripts/common.sh`.
  GPL-3.0 and AGPL-3.0 parts are combined here under section 13 of both licences; the combination is AGPL-3.0, and the
  GPL-3.0 parts keep their own terms.
- **Leafia Plus NEEV.KOR.03-r8.2** (`wireless.cp.aa.neev.kor`, the Korean port of HMG Leafia Plus 1.0.5): the
  `neev_kr` patch set (corrected Korean turn-by-turn builds, the UTF-8 receiver fix, the lane helpers, the
  PhoneProjection bridge, the Korean CarPlay owner corrections), the Korean stock md5s of PhoneProjection, and the
  `persist.leafia.*` switch names and defaults (its `LEAFIA-KR-SETTINGS.ini` and `kr-lifecycle/settings.sh`). Its
  notice is kept as `LICENSES/ORIGINAL_FLOW_NOTICE-leafia-kr.txt`; it ships under the same GPL-3.0 / AGPL-3.0 terms.
- **CarPlay turn-by-turn maneuver fix** by Isaac Wisdom (https://github.com/isaacwisdom): the DiPO route-guidance
  parser wrote maneuver indexes into a copy of the index array, so every maneuver read as -1. Applied by Leafia to the
  EV6, Ioniq 5 and K5 builds; it reaches the car through those sets' HKMC_DiPO patches.
- **`package/tools/codesum.jar`** (0.1.3, JMK's own, AGPL-3.0): built from `src/jmkhud/CodeSum.java` by
  `src/build-codesum.sh` (javac + the Android SDK's d8, a fixed timestamp, so the same source gives the same bytes),
  sha256 bd08914c7713ec97d66ebe16159de940730f8f8df9611ee1bd5a5ce7ce3ad30c. It reads the md5 of the dex inside an app's odex for the locked report.
- **gen5w-Evergreen** by zpoon (https://github.com/zpoon/gen5w-Evergreen, commit 573fdae), GPL-3.0, a community fork of
  HMG Leafia Plus: the `nq5` (Kia Sportage / Sportage Hybrid, US 260507) and `neev23_260903` (Hyundai Ioniq 5 US
  260903) patch sets and their `patches/cars` lines, unmodified (0.1.2). Its notice is kept as
  `LICENSES/UPSTREAM_NOTICE-gen5w-evergreen.md`; combined here under section 13 as above.
  0.1.4: its universal patches (`patches/universal/`, unmodified) as the by-code profile `patches/bycode/us`.
- **By-code profile `kr`** (`patches/bycode/kr`, 0.1.4): the `neev_kr` set's builds (Leafia Plus NEEV.KOR.03-r8.2,
  above) keyed to the code inside each stock .odex instead of the .odex file, made by `src/mkbycode.py` (JMK's own,
  AGPL-3.0) from that set and the Ioniq 5 Korea stock files: the same result code, for Korean head units whose apps
  run the same code (K8 Hybrid Korea, first seen 2026-11-17). Only deltas and md5s; no stock file ships.
- Thanks, as upstream: W-Floyd.

No manufacturer APK, odex, jar or library is shipped: the head unit rebuilds each file from its own exact stock copy,
and every patch checks the stock md5 (or the stock bytes, for a recipe) first.

## What this fork changes (relative to projection.tbt and Leafia's parts)

- One NEMESIS package (`jmk-autoplay-hud`) with only Leafia's parts 2_tbt and 3_bridge plus the CarPlay library
  recipes. Not included: part 1_projection (the wireless feature flags: JMK Wireless AutoPlay does that), the
  BtSettings menu patch (5_menu), the KR Wi-Fi provider (kr-grt-usbwifi), Leafia's KR lifecycle/updater/recovery,
  the iAP2 properties (`persist.sys.iap2.wifi`, `persist.iap2.iden.wireless`: JMK Wireless AutoPlay owns them).
- The final file of each target is rebuilt in one step: where Leafia installs the 2_tbt build of HKMC_DiPO /
  Iap2ServerApp and then the 3_bridge build over it, this package installs the 3_bridge build directly (both patches
  start from the same stock odex; the end state is the same file).
- /system is never remounted read-only (on the target car it is read-write by design); NEMESIS is asked for
  read-write only when /system is found read-only.
- dalvik-cache removal is best effort: root without capabilities (an install over adb) cannot remove the entries;
  that is logged and never stops an install or an uninstall.
- One stock-md5 gate for every target of the car's set before anything is written; a mismatch leaves the car as it
  is (`state=locked` with the file named). A product that patches/cars does not name may use a set whose stock files
  all match exactly. Recipes check themselves and are skipped when they do not fit.
- Every file written is recorded with its md5; a real uninstall puts every stock file back byte-identical (md5
  checked) and removes the converter it added; an update keeps the patched files.
- Only apps that are enabled are stopped for the file swap, and the same ones are started again (also by the
  settings service at boot, if a run died).
- A status file for the JMK MAP menu (`/data/nemesis/jmk-autoplay-hud/status`) and a settings service that maps the
  menu's config keys to the `persist.leafia.*` switches the patched apps read.
- First install needs JMK Wireless AutoPlay and refuses next to another phone-projection package.

## Binaries and their sources (GPL-3.0 section 6)

`package/tools/lpatch` and `package/files/libev6aac.so` are HMG Leafia Plus 1.0.5's own GPL-3.0 builds, shipped
unmodified. Their Corresponding Source is the HMG Leafia Plus project's published source; the link must be added
here before this package is published (TODO before publishing).
