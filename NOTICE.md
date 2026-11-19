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
- **By-code profile `krb`** (`patches/bycode/krb`, 2026-11-19): the `kr` profile's turn-by-turn builds keyed to the
  code of Korean head units (Santa Fe TM facelift TMFL, Sonata DN8 / DN8 Hybrid, Avante Hybrid CN7HEV22, one Palisade LX2 firmware) whose
  apps are Ioniq 5 Korea's app code dexopted against a framework with one `Message` / `WifiManager` method fewer (so
  only quick-call vtable indices differ in the .odex); HKMC_Navi_ExSL's build also carries that framework's two string
  IDs. 2026-11-20, the CarPlay bridge part: their PhoneProjection is the Tucson's stock code (`krt`) with other
  ProGuard names and the Tucson's resources, so its bridge build is `krt`'s (Leafia's `neev_kr` bridge build with eight
  drawable IDs changed), and HKMC_DiPO / Iap2ServerApp end at the `kr` profile's bridge builds. Only deltas and md5s;
  no stock file ships.
- **By-code profile `kra`** (`patches/bycode/kra`, 2026-11-19): the `kr` profile for Korean K8, K8 Hybrid and Seltos
  head units (GL3, GL3HEV, SP2PE V039.001.260902), whose apps run Ioniq 5 Korea's app code. Their PhoneProjection is
  Ioniq 5 Korea's stock code as well, built with their own resource table, so its CarPlay bridge build is Leafia's
  `neev_kr` bridge build with the same 12 constants changed: eight drawable IDs of their apk and the
  `android:id/topPanel` of their framework. Only deltas and md5s; no stock file ships. `scripts/common.sh` uses the
  by-code profile that fits the most parts.
- **By-code profile `krt`** (`patches/bycode/krt`, 2026-11-19): the `kr` profile for Korean Tucson and Tucson Hybrid
  (NX4, NX4HEV V039.001.260902). Their PhoneProjection is Ioniq 5 Korea's stock code built with the K8's resource
  table (their framework keeps `android:id/topPanel` where the Ioniq 5 has it), so its CarPlay bridge build is Leafia's
  `neev_kr` bridge build with eight drawable IDs (11 constants) changed. Only deltas and md5s; no stock file ships.
- **By-code profile `krp`** (`patches/bycode/krp`, 2026-11-19): Korean Avante facelift and Avante N facelift (CN7PE,
  CN7NPE V039.001.260902), whose apps are Ioniq 5 Korea's app code with other ProGuard names on the same framework
  layout: every result is the `kr` profile's own build (PhoneProjection's the same bridge build as `krt`'s), reached
  from their code. No receiver-library line: their libautoreceiver_infobank.so is another build. Only deltas and md5s.
- **By-code profile `kre`** (`patches/bycode/kre`, 2026-11-19): Korean Kia EV6 (CVEV.KOR V039.001.260902), whose apps
  are Ioniq 5 Korea's app code with other ProGuard names: GPM, DiPO, Navi and Iap2ServerApp end at the `kr` profile's
  own builds; PhoneProjection's bridge build is `kr`'s with `android:id/topPanel` at their framework's number; and the
  receiver library carries `kr`'s turn-by-turn hook with its links and patched instructions moved to EV6's own library
  layout (same symbols, other addresses). Only deltas and md5s; no stock file ships.
- **By-code profile `kri`** (`patches/bycode/kri`, 0.1.10, 2026-11-20): Korean Ioniq 6 (CEEV.KOR V039.001.260902).
  Its HKMC_GPM, HKMC_DiPO and HKMC_Navi_ExSL run the Avante CN7 PE's code (`krp`), Iap2ServerApp the Ioniq 5's, and its
  PhoneProjection is Ioniq 5 Korea's stock code with other ProGuard names, with the Ioniq 5's resources byte for byte:
  every result is the `kr` profile's own build (PhoneProjection's Leafia's `neev_kr` bridge build itself). No
  receiver-library line: its libautoreceiver_infobank.so is CN7 PE's build. Only deltas and md5s; no stock file ships.
- **By-code profile `krg`** (`patches/bycode/krg`, 0.1.10, 2026-11-20): Korean Genesis G70 facelift (IKFL.KOR
  V039.001.260902), whose apps and receiver library run Ioniq 5 Korea's code. Its PhoneProjection is Ioniq 5 Korea's
  stock code built with its own resource table, so its CarPlay bridge build is Leafia's `neev_kr` bridge build with
  eight drawable IDs (11 constants) set to its numbers. Only deltas and md5s; no stock file ships.
- **Korea Projection** by StopDragon (https://github.com/StopDragon/korea-projection, release 1.7.4; its wireless mode
  2.4.4 in the HMG-API fork https://github.com/StopDragon/HMG-API, branch korea-build, commit b573ac6,
  `mods/wireless-carplay-aa/src/hmgapi/mods/wireless/dipo/CpTurnsFit.java` `near()`), AGPL-3.0: the method of the
  0.1.11 near-turn fixes (put-off, jump-hold, the exit margin at the window edge and their constants: 50 m margin,
  100 m / 20 m jumps, 10 m rise within 500 ms), worked out from its car logs (Naver Map, KakaoNavi). Its code is not
  copied: `src/tbt/com/jmk/hud/Near.java` is our own (AGPL-3.0, as this package), adapted to Leafia's fixed 457 m window.
- **The 0.1.11 near-turn filter** (`src/tbt/`, JMK's own, AGPL-3.0): `com.jmk.hud.Near` and four hooks on Leafia KR's
  `com.leafia.kr` code (`near-hooks.diff`: LeafiaTurn.standard / reset, LeafiaCpStandard.format / routeReset), built
  into the GPM turn-by-turn and DiPO bridge results of every Korean set and profile by `src/tbt/build.sh` (javac + d8,
  baksmali / smali 2.5.2 with one thread, so the same inputs give the same bytes: GPM 990ef4c3 -> b02ada70, DiPO
  86ce5550 -> 1452d2d8).
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
- 0.1.8: a stock copy goes back only over a file this package wrote. A file that is neither (after a firmware update:
  the new firmware's own apk, odex or library) is left alone and its record dropped; ro.build.fingerprint is kept
  with the records, which a firmware change makes true to the new firmware. An update only on a positive signal
  (the parent is an install, the package staged). An update puts back what its targets no longer name, and one
  whose patches do not fit keeps (and reports) the earlier version's files. Free space is checked before the swap.
  The settings service checks the patched files at every boot (also when active). The log is capped; copies a
  cut-off swap left are removed.
- 0.1.11: the near-turn layout ("big picture") of the Korean GPM and DiPO bridge builds. A picture that went near
  stays near up to 50 m past Leafia's 457 m window (Android Auto and CarPlay: distance wobble at the edge flipped it).
  CarPlay only: a new maneuver whose first distance is the previous maneuver's last one is shown far once (Naver Map
  order: the next turn's picture flashed for about a second), and a jump of the same maneuver's distance is held once
  (KakaoNavi order: the passed turn's picture with the next distance's bar). Every other input keeps Leafia's value.
- Only apps that are enabled are stopped for the file swap, and the same ones are started again (also by the
  settings service at boot, if a run died).
- A status file for the JMK MAP menu (`/data/nemesis/jmk-autoplay-hud/status`) and a settings service that maps the
  menu's config keys to the `persist.leafia.*` switches the patched apps read.
- First install needs JMK Wireless AutoPlay and refuses next to another phone-projection package.

## Binaries and their sources (GPL-3.0 section 6)

`package/tools/lpatch` and `package/files/libev6aac.so` are HMG Leafia Plus 1.0.5's own GPL-3.0 builds, shipped
unmodified. Their Corresponding Source is the HMG Leafia Plus project's published source; the link must be added
here before this package is published (TODO before publishing).
