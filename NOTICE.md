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
  no stock file ships. 0.1.17: also the turn-by-turn part of the cars of Leafia's `dl3hev` set (Kia K5, K5 Hybrid,
  Sorento Hybrid, K7, Stinger, Niro Hybrid Korea V039): the same app code.
- **By-code profile `krk`** (`patches/bycode/krk`, 0.1.20): `krb`'s lines word for word for the Kia Niro Hybrid Korea
  (DEPEHEV V039), whose PhoneProjection is group B's code with K8's `android:id/topPanel` number; its PhoneProjection
  bridge is `kra`'s build (Leafia's `neev_kr` bridge build with eight drawable IDs and topPanel changed). Compared with
  JMK's own tools (AGPL-3.0, private/hud-port/depehev-v039). Only one delta and md5s; no stock file ships.
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
  own builds; PhoneProjection's bridge build is `kr`'s with `android:id/topPanel` at their framework's number. Only
  deltas and md5s; no stock file ships. No receiver-library line since 0.1.15 (2026-11-20): 0.1.7-0.1.14 carried `kr`'s
  turn-by-turn hook moved to EV6's own library layout. That hook raises the Android Auto navigation protocol 1.4 -> 1.6
  and parses messages 0x8006 / 0x8007, and an EV6 Korea owner had Android Auto dropping with Naver Map. EV6's library
  now stays stock (turn-by-turn by the stock NextTurn path, as `krp` / `kri`), and an update puts a patched one back
  to its stock copy.
- **By-code profile `kri`** (`patches/bycode/kri`, 0.1.10, 2026-11-20): Korean Ioniq 6 (CEEV.KOR V039.001.260902).
  Its HKMC_GPM, HKMC_DiPO and HKMC_Navi_ExSL run the Avante CN7 PE's code (`krp`), Iap2ServerApp the Ioniq 5's, and its
  PhoneProjection is Ioniq 5 Korea's stock code with other ProGuard names, with the Ioniq 5's resources byte for byte:
  every result is the `kr` profile's own build (PhoneProjection's Leafia's `neev_kr` bridge build itself). No
  receiver-library line: its libautoreceiver_infobank.so is CN7 PE's build. Only deltas and md5s; no stock file ships.
- **By-code profile `krg`** (`patches/bycode/krg`, 0.1.10, 2026-11-20): Korean Genesis G70 facelift (IKFL.KOR
  V039.001.260902), whose apps and receiver library run Ioniq 5 Korea's code. Its PhoneProjection is Ioniq 5 Korea's
  stock code built with its own resource table, so its CarPlay bridge build is Leafia's `neev_kr` bridge build with
  eight drawable IDs (11 constants) set to its numbers. Only deltas and md5s; no stock file ships.
- **By-code profile `krv`** (`patches/bycode/krv`, V037, 0.1.14): Hyundai Ioniq 5 Korea on the older firmware
  NEEV.KOR.0000.V037.001.260319, whose apps are an older source revision of Ioniq 5 Korea's (another ProGuard run,
  some methods changed or missing, dexopted against an older framework). Turn-by-turn only: each result is that car's
  own stock code with the `kr` profile's turn-by-turn changes (Leafia's `neev_kr` build plus ours) ported onto it, made
  by JMK's own tools (AGPL-3.0, private/hud-port/neev-v037/tools: deodex at the Dalvik field layout, the odex quick-call
  slots checked against the Ioniq 5's code, the V037 classes put into the `kr` build under its names, per-member merge);
  the receiver library is Ioniq 5 Korea's, so its line is `kr`'s. Only deltas and md5s; no stock file ships.
- **By-code profiles `krc` and `krd`** (`patches/bycode/krc`, `patches/bycode/krd`, V035, 0.1.16): Kia Carnival KA4 and
  Hyundai Tucson Hybrid NX4HEV Korea (`krc`, the same app code) and Kia K5 Hybrid DL3HEV Korea (`krd`) on the older
  firmware .KOR.0000.V035.001.250507, whose apps are an older source revision still than V037's. Turn-by-turn only, made
  as `krv`'s by the same JMK tools (AGPL-3.0, private/hud-port/v035/<group>/tools): each result is that car's own stock
  code with the `kr` profile's turn-by-turn changes (Leafia's `neev_kr` build plus ours) ported onto it. Iap2ServerApp
  runs V037's code (`krc`: `krv`'s line; `krd`: its own delta to `krv`'s result). No receiver-library line (another build
  of the library). Only deltas and md5s; no stock file ships.
- **By-code profile `krm`** (`patches/bycode/krm`, V037, 0.1.18): Kia Sorento MQ4 Korea (and the Hyundai Grandeur IGPE
  Korea, the same code) on the firmware .KOR.0000.V037.001.260319. Their apps are `krv`'s app code (the Ioniq 5 Korea
  V037's) dexopted against another framework, with group B's core.odex and one `Message` / `UsbDevice` / `WifiManager`
  method fewer, so only quick-call vtable indices differ in the .odex. Deodexed by the same JMK tools (AGPL-3.0,
  private/hud-port/mq4-v037/tools), the plain code is `krv`'s byte for byte. Turn-by-turn only: HKMC_GPM and HKMC_DiPO
  end at `krv`'s builds, Iap2ServerApp runs `krd`'s code (`krd`'s line), and HKMC_Navi_ExSL ends at `krv`'s build with
  that framework's two string IDs. The receiver library is Ioniq 5 Korea's, so its line is `kr`'s. Only deltas and
  md5s; no stock file ships.
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
- **The 0.1.13 wireless iAP2 fix** (`src/tbt/wireless-iap2.diff`, JMK's own, AGPL-3.0): the stock HKMC_DiPO code's
  transport check (`if-eq p1, Wireless` in `com.daudio.app.dipo.e.b` `e(I)` / `f(I)`: setStartiAP2Service /
  setStopiAP2Service) is taken out, so a wireless CarPlay session also starts / stops the iAP2 now-playing and
  telephony updates. Applied to the DiPO tree by `src/tbt/build.sh` after `near-hooks.diff`: DiPO 86ce5550 ->
  d760fe5b (0.1.11's 1452d2d8 with this diff alone gives the same bytes). The only change against 1452d2d8 is those
  two instructions (and the branch offsets after them).
- **The 0.1.18 CarPlay-channel iAP2 resume** (`src/tbt/cp-iap-resume.diff`, JMK's own, AGPL-3.0): a hook in Leafia's
  `com.ev6.cpwl.Bridge.dipoDropNoti(I)` where the bridge drops noti 0 (identification accepted) of the CarPlay-channel
  iAP2 session, and a new class `com.ev6.cpwl.CpIapResume` that, on wireless CarPlay, calls the stock DiPO's
  `com.daudio.app.dipo.e.b` `e(I)` (setStartiAP2Service) once more for that session, from the bridge's handler, each
  with its own try/catch; the noti stays dropped. Applied by `src/tbt/build.sh` after `wireless-iap2.diff` to the tree
  with `com/ev6/cpwl/Bridge.smali`: DiPO 86ce5550 -> 56d9ff80 (0.1.13's d760fe5b with this diff alone gives the same
  bytes). The only changes against d760fe5b are that hook (and the branch offsets after it) and the new class.
- **The 0.1.19 turn-by-turn release and TBT_CLEAR receiver** (`src/tbt/tbt-clear.py`, `src/tbt/clear.sh`,
  `src/tbt/com/jmk/hud/TbtClear.java` and its compile-only `src/tbt/stubs/com/hkmc/cluster/NavigationCluster.java`,
  JMK's own, AGPL-3.0): in the patched HKMC_GPM, `GpmNaviTBTManager.destroy()` (the stock session end) first runs
  `onStatus(0)` (the stock release path) when that manager drew on the cluster, `claimCluster` keeps it for
  `jmkClear`; in the patched HKMC_DiPO, `e/m.onSessionFinalized` calls `e/u.jmkEnd()` after the stock
  `disconnected()`, which sends `TbtClear.release` (the GPM release's cluster calls) and the stock `sendHudBlank`
  when the last TBT_INFO was not DisplayType 8 (`jmkMark` before the one send); both services' onCreate register
  `com.jmk.hud.TbtClear` for `com.jmk.hud.TBT_CLEAR` at runtime. Applied last by `src/tbt/build.sh`, or by
  `src/tbt/clear.sh` to a 0.1.18 result: GPM b02ada70 -> d2538947, DiPO bridge 56d9ff80 -> 913848d6 (0.1.10's
  990ef4c3 / 86ce5550 through build.sh give the same bytes), and the other Korean GPM / DiPO results (README, 0.1.19).
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
- 0.1.15: the by-code build reads its stock files only from verified stock copies: the copy in the backups when its
  md5 is the recorded stock one, the live file only when that is the stock one or when nothing of it was ever
  recorded. Before, a file an earlier version patched could be read as stock when the ownership record did not
  recognise it. The update then kept the earlier build for good, or kept our patched apk as the stock copy. The gate
  and the put-back now share one ownership rule.
- 0.1.16: turn-by-turn on the Korean V035.001.250507 firmware (profiles `krc`, `krd`); no script change.
- 0.1.17: the tamper lock is held by every postinstall and the settings service through one function (`lock_hold`):
  an install or update while the JMK MAP menu says `lock=1` writes nothing, and puts back anything of ours that is
  live. `patches/known` (`src/mkknown.py`, JMK's own, AGPL-3.0) lists every result an earlier version wrote: ours()
  counts those, so such a file is rebuilt from its verified stock copy (and is never read as a stock file). A fixed set
  with a `superseded` file (`dl3hev`, Leafia's original K5 Hybrid build) is the fallback behind the by-code profiles,
  so its cars get `krb`'s turn-by-turn builds.
- 0.1.18: turn-by-turn on the Kia Sorento MQ4 Korea V037.001.260319 (profile `krm`, also the Grandeur IGPE V037); no
  script change.
- 0.1.11: the near-turn layout ("big picture") of the Korean GPM and DiPO bridge builds. A picture that went near
  stays near up to 50 m past Leafia's 457 m window (Android Auto and CarPlay: distance wobble at the edge flipped it).
  CarPlay only: a new maneuver whose first distance is the previous maneuver's last one is shown far once (Naver Map
  order: the next turn's picture flashed for about a second), and a jump of the same maneuver's distance is held once
  (KakaoNavi order: the passed turn's picture with the next distance's bar). Every other input keeps Leafia's value.
- 0.1.13: the Korean DiPO bridge builds start the iAP2 now-playing, call-state and telephony updates for a wireless
  CarPlay session too (the stock code started them for USB only): the stock split view's now playing and the
  steering-wheel call button's call state on wireless CarPlay, as on USB.
- 0.1.18: 무선 카플레이에서 분할화면 곡 정보·재생 시간·통화 상태가 계속 바뀝니다: the Korean DiPO bridge builds start the
  iAP2 now-playing, call-state and telephony updates once more on the CarPlay-channel iAP2 session that wireless
  CarPlay moves to after connecting; wired CarPlay unchanged.
- 0.1.19: 안드로이드 오토·카플레이가 끊기거나 종료되면 계기판·HUD 길안내가 바로 사라집니다: the GPM and DiPO builds with
  our turn-by-turn code release the cluster / HUD guidance at the stock end of the projection session, and take
  `am broadcast -a com.jmk.hud.TBT_CLEAR` (root, system or shell) to release it by hand.
- 0.1.20: 기아 니로 하이브리드에서 무선 카플레이 + 계기판 · HUD 길안내가 됩니다 (profile `krk`: `krb`'s builds and
  `kra`'s PhoneProjection bridge build); no script change.
- Only apps that are enabled are stopped for the file swap, and the same ones are started again (also by the
  settings service at boot, if a run died).
- A status file for the JMK MAP menu (`/data/nemesis/jmk-autoplay-hud/status`) and a settings service that maps the
  menu's config keys to the `persist.leafia.*` switches the patched apps read.
- First install needs JMK Wireless AutoPlay and refuses next to another phone-projection package.

## Binaries and their sources (GPL-3.0 section 6)

`package/tools/lpatch` and `package/files/libev6aac.so` are HMG Leafia Plus 1.0.5's own GPL-3.0 builds, shipped
unmodified. Their Corresponding Source is the HMG Leafia Plus project's published source; the link must be added
here before this package is published (TODO before publishing).
