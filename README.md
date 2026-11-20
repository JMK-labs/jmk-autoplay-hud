# jmk-autoplay-hud: JMK AutoPlay 확장 (HUD · 계기판 길안내)

An add-on NEMESIS package for Korean Gen5W head units (developed on a 2023 Ioniq 5, NEEV.KOR 260902): the CarPlay
Bluetooth bridge that wireless CarPlay needs on the Korean firmware, and Android Auto / CarPlay turn-by-turn on the
stock cluster and HUD. It sits on top of JMK Wireless AutoPlay (`jmk-autoplay`, which turns the stock wireless
features on).

**Licence: AGPL-3.0** (`LICENSE`), a fork of the NEMESIS community package projection.tbt with HMG Leafia Plus's GPL-3.0
bridge, recipes and lpatch: see `NOTICE.md`. Source: https://github.com/JongMinKim-93/jmk-autoplay-hud. Nothing in this
package is obfuscated. No code of it goes into any other JMK package, and none of theirs into it.

## What it changes on the head unit

The patch set comes from `ro.build.product` (`package/patches/cars`). Each target is rebuilt on the head unit from its
own stock file with lpatch, only when that file has the exact stock md5 the set names:

| set | car (patches/cars) | targets (part) |
|---|---|---|
| `neev_kr` | Hyundai Ioniq 5 Korea, NEEV.KOR.0000/S5W_M.V039.001.260902 | HKMC_GPM, HKMC_Navi_ExSL, libautoreceiver_infobank.so (2_tbt); Iap2ServerApp, HKMC_DiPO, PhoneProjection (3_bridge) |
| `neev` | Hyundai Ioniq 5 (US), NEEV.USA. / NEEV23.USA. | HKMC_GPM, HKMC_Navi_ExSL, libautoreceiver_infobank.so (2_tbt, common lib); Iap2ServerApp, HKMC_DiPO (3_bridge) |
| `neev_ca` | Hyundai Ioniq 5 (Canada), NEEV.CAN. | as `neev` (own lib patch) |
| `ev6` | Kia EV6 (US), CVEV.USA. | as `neev` |
| `ev6_ca` | Kia EV6 (Canada), CVEV.CAN. | as `neev` (ev6 patches, Canadian stock apks) |
| `dl3hev` | Kia K5 Hybrid Korea (and every Korean V039 car with exactly its stock files) | as `neev`; patches/cars has no line for it (as Leafia's Korean port ships it): reached only when its stock files all match. 0.1.17: superseded (Leafia's original build): those cars get the by-code profile `krb`, the set only when no profile fits |

Plus the CarPlay library recipes, each checked on its own file: `carplay-utils-converter` (libCarPlayUtils.so, with
`libev6aac.so`), `carplay-audio-formats` (libCarPlayAudio.so: AAC music, Opus voice over Wi-Fi) and
`carplay-core-wifi` (libCarPlayCore.so). On NEEV.KOR 260902 only the audio one applies (the other two are NATIVE).
`os="*.KOR.*"` in NEMESIS.data limits installs to KOR firmware; the other sets are kept for other models.

0.1.17: the tamper lock holds through updates, our own earlier builds are ours again, and the cars of Leafia's K5 Hybrid
set get our builds.
- **The tamper lock now holds through installs and updates.** Before, only the settings service read the lock, once at
  its start: it put every stock file back, dropped the records and wrote a mark. An install or an update while the
  lock said `lock=1` (from NEMESIS, NEMESIS Manager or the MAP menu) then saw a stock car with no records and patched
  it like a fresh install. The service NEMESIS starts after every update found the mark and did nothing, so the car
  ran patched files while the menu said it was locked. Now one hold (`lock_hold` in `scripts/common.sh`) is the first
  step of every postinstall and of the service's start. While the lock says 1, nothing is built or written, anything
  of ours that is live goes back (the uninstall's ownership-checked put-back), and the state says the lock's text. The
  add-on is applied again only by the lock's own rule, once the MAP menu no longer says `lock=1`: at that install or
  at the service's next start. The mark goes only with a postinstall that applies. The service also puts back a car
  an earlier version re-patched while it was locked (mark and records both there).
- **Our own earlier builds are ours (GMI6OZC2, Ioniq 5 Korea, locked since 0.1.13).** Its HKMC_GPM.apk is 1c4bfdda,
  the `neev_kr` GPM build of 0.1.0–0.1.4 (byte for byte Leafia KR r8.2's). The applied record has no line for it, so
  every version since took it for another tool's file ("not the stock file"). `patches/known` (made by
  `src/mkknown.py` from every version of the manifests and every built zip) lists every rebuilt apk of a fixed set
  and every rebuilt library any version wrote. `ours()` counts those, so the gate rebuilds such a file from its
  verified stock copy (`stock_copy()`, the 0.1.15 rule), and the by-code build never reads one as a stock file.
  Without a stock copy, nothing changes, and the reason now says "a build of this add-on … but its stock copy … is not
  in …". The locked report also names what Leafia's own snapshots (`/data/nemesis/backup/projection.tbt`,
  `wireless.carplay.bt`) still hold of the stock files. GMI6OZC2 has neither a record nor a copy of ours, so it stays
  locked (said so). A build of this version found in place without its applied line is recorded again.
- **The `dl3hev` set is superseded (about 17 cars).** It is Leafia's original build for the K5 Hybrid Korea,
  unchanged since projection.tbt: none of our changes (0.1.5, the 0.1.11 near-turn filter) and no settings. Every
  Korean V039.001.260902 car with exactly its stock files took it, by file match: DL3, DL322, DL3HEV22, MQ422HEV,
  MQ4HEV, YGPE, CKPE, DEPEHEV. Their GPM, DiPO, Iap2ServerApp and Navi code is group B's. Every one of Leafia's six
  dl3hev deltas rebuilds its exact target md5 from group B's stock code and from no other car's. A set with a
  `superseded` file is now the fallback: the by-code profiles come first. These cars get `krb`'s turn-by-turn builds:
  GPM b02ada70 (0.1.5, near-turn), DiPO ffe9b558, Iap2ServerApp 02368c25, Navi 44b26803 and the library aba7787c,
  each in the car's own apk, with the menu's settings. An update from `dl3hev` builds them from the verified stock
  copies.
- **The CarPlay bridge stays held for these cars.** The Leafia `dl3hev` bridge (the old DiPO / Iap2ServerApp
  wireless.carplay.bt builds, no PhoneProjection) goes with the set. A DL3 owner's log shows it doing nothing:
  Bluetooth iAP2 connects, then drops ("응답이 없습니다"). krb's bridge was checked against DL3HEV22's own boot class
  path (16 odex files from 카플레이용 파일 보내기): every call binds as on group B, the supertypes are the same, and
  baksmali's full analysis gives no error. But that car's framework-res has `android:id/topPanel` at 0x010202f0, as
  K8's does. Its PhoneProjection therefore cannot be group B's (4e8915b2), so krb's bridge part does not fit. The car
  checks that code itself. The other-model-set report now names that code, so a bridge can be built.
  private/hud-port/hud-0117-REPORT.md. Not car-tested.

0.1.16: turn-by-turn for the Korean cars on the older firmware .KOR.0000.V035.001.250507 (by-code profiles `krc`, `krd`).
- **`krc`: Kia Carnival KA4 and Hyundai Tucson Hybrid NX4HEV V035** (DWWOLTJU, 2DUGUSW2: the same GPM, DiPO, Navi,
  Iap2ServerApp and library code). V035 is an older source revision than V037 (`krv`) and V039 (`kr`). Each result is
  the car's own stock code with kr's turn-by-turn changes ported on (the 0.1.11 near-turn filter included), as krv's.
  Iap2ServerApp is V037's code, so its line is krv's.
- **`krd`: Kia K5 Hybrid DL3HEV V035** (325RLNAK): the same source as KA4 V035 with other ProGuard names and another
  framework (group B's quick-call slots); its Iap2ServerApp differs from V037's by one quick slot.
- Turn-by-turn only. No receiver-library line (their library is another build; kre's moved hook broke Android Auto). The
  CarPlay bridge was built for KA4 and DL3HEV but is held back: V035's framework, framework-res and Broadcom / iap2
  libraries are needed to check it (카플레이용 파일 보내기). Unproven on these cars: `USMManager.getDistanceSpeedUnit()`
  and `TurnList.<init>()` (as on V037). Report: private/hud-port/v035-REPORT.md. Not car-tested.

0.1.15: an update over files an earlier version patched builds from the stock copies again, and the
EV6 Korea profile leaves the receiver library stock.
- **Kept-old after an update (DPPB5BHV, Kia EV6 Korea, 2026-11-19).** 0.1.9 updated it fine (profile `kre`), then 0.1.10
  reported `postinstall-kept-old` "nor its code a profile" and kept 0.1.9's build. Cause (`scripts/common.sh`): before
  any set is known, the by-code build took its stock files from `plan_src()`. That gave "our copy in the backups when
  the live file is ours, else the live file", and "ours" was only "the apk's md5 is in the applied record". When that
  said no for a file an earlier version had patched, the live, patched odex was read as the stock one. Its code is
  the patched code, so no profile fit, and every later version kept the old build. One state that does it: a put-back
  (an uninstall, a rollback, the tamper lock's) cut off between an app's apk and its odex, an odex the put-back itself
  counts as ours. The copy was never md5-checked either: with a stock copy lost, the update took our patched apk for
  the stock one and kept it as the "stock copy". The reports cannot show which file DPPB5BHV hit. The 0.1.9 report's
  patched codes are not the cause: that report read the live odex, which after any update is our own build.
- **Now:** `stock_copy()` gives the copy in the backups whenever its md5 is the recorded stock one, the live file only
  when it is the recorded stock one (or when nothing of it was ever recorded and it is not ours), and otherwise
  nothing. A patched file is never a stock source. Whose the live file is decides only whether it may be replaced:
  the gate and the put-back share one `ours()`, which also counts an odex next to the recorded stock apk on the same
  firmware. The other-model-set report names the stock code the profile was chosen by. The locked / kept-old reports
  add "by code: …": which stock copy was missing, which profile did not build, or that the code helper gave no answer.
- **Profile `kre` has no receiver-library line any more** (the owner's call). 0.1.7–0.1.14 put kr's library hook,
  moved to EV6's library, into libautoreceiver_infobank.so (result 120bab2c). That hook raises Android Auto's navigation
  protocol 1.4 → 1.6 and parses messages 0x8006 / 0x8007. DPPB5BHV's owner has Android Auto dropping while driving with
  Naver Map only. Turn-by-turn now goes the stock NextTurn path, as on `krp` / `kri`. An update puts a library an
  earlier version patched back to its stock copy (ownership-checked, like any file the targets no longer name). A
  fresh install leaves it stock.
- A DPPB5BHV-like car that installs 0.1.15 rebuilds GPM, DiPO, Iap2ServerApp, Navi and PhoneProjection from its stock
  copies (kre's current builds) and puts its stock library back. If something else wrote one of its files, the gate
  keeps the earlier build and the report names the file. Not car-tested.

0.1.14: turn-by-turn for the Ioniq 5 Korea on the older firmware NEEV.KOR.0000.V037.001.260319
(by-code profile `krv`). Its apps are an older source revision of the V039 ones, so no existing profile fitted (the
add-on stayed locked). Each krv result is that car's own stock code with the kr profile's turn-by-turn changes ported
onto it (HKMC_GPM, HKMC_DiPO, Iap2ServerApp, HKMC_Navi_ExSL; the receiver library is the Ioniq 5's, so kr's line).
Turn-by-turn only: the CarPlay bridge waits for that firmware's framework and Broadcom library to be checked. Only
deltas and md5s; no stock file ships. Not car-tested.

0.1.13: wireless CarPlay now playing and call state. Owners saw no track in the stock split view with wireless
CarPlay (USB showed it), and the steering-wheel call button put a wireless CarPlay call on hold instead of ending it.
Cause: the stock HKMC_DiPO code (`setStartiAP2Service` / `setStopiAP2Service`, class `com.daudio.app.dipo.e.b`)
starts and stops the iAP2 now-playing, call-state and telephony updates only when the transport is not Wireless, and
the bridge builds kept that. `src/tbt/wireless-iap2.diff` takes out exactly those two transport checks
(`if-eq p1, Wireless`), so a wireless session starts them as a USB one does; nothing else changes. Every Korean DiPO
bridge build (by-code kr, kra, krb, kre, krg, kri, krp, krt and the `neev_kr` set) ends at the new result d760fe5b
(was 1452d2d8); rebuild: `src/tbt/build.sh <0.1.10 result dex> <out dex>`. The other sets are unchanged. Not
car-tested.

0.1.12: the CarPlay bridge for group B (`krb`: Santa Fe TM FL, Sonata DN8 / DN8 HEV, Avante Hybrid CN7HEV22, Palisade
LX2 V039.001.260902). Their PhoneProjection (4e8915b2) is the Tucson's stock code with other ProGuard names, checked
against a CN7HEV car's own boot class path (16 odex files from 카플레이용 파일 보내기): the bridge is krt's / krp's
build, DiPO and Iap2ServerApp end at kr's bridge builds. Only deltas and md5s; no stock file ships. Not car-tested.

0.1.11: the Korean GPM and DiPO bridge builds (every Korean set and by-code profile) carry our near-turn filter
(`src/tbt/`, method from Korea Projection 1.7.4): the near-turn picture no longer flips at the 457 m edge (50 m exit
margin), and on CarPlay the next turn's picture no longer flashes when the phone sends the new maneuver with the old
distance (Naver Map) or the next distance on the old maneuver (KakaoNavi). Rebuild: `src/tbt/build.sh <0.1.10 result
dex> <out dex>`; test: `test/near/com/jmk/hud/NearTest.java` (run by `test/check-scripts.sh`).

Where Leafia installs the 2_tbt build of HKMC_DiPO / Iap2ServerApp and then its 3_bridge build, this package puts the
3_bridge build in directly: both patches start from the same stock odex, and the end state is the same file.

## Install, update, uninstall

- **preinstall**: a first install needs `jmk-autoplay` installed and refuses next to another phone-projection package
  (Leafia, the upstream NEMESIS projection packages, Evergreen, 단풍, Korea Projection, aa.usbwifi, an HMG-API mod).
  An update always goes ahead.
- **postinstall**: the gate checks every target first; a file that is neither the stock one nor ours: `state=locked`,
  nothing changed. Then everything is rebuilt into `/data/nemesis/jmk-autoplay-hud/build`, the stock copies go to
  `/data/nemesis/backups/jmk-autoplay-hud` (md5-checked), the enabled apps among them are stopped, the files go in
  (beside + rename), odex rewritten with dexopt, dalvik-cache cleared/filled where root may, the apps started again.
  Any failure puts every stock file back (`state=failed`). Then `state=reboot`: restart the head unit.
- **update** (NEMESIS runs the old preuninstall with the new package staged): the patched files stay; the new
  postinstall rebuilds only what changed.
- **uninstall**: every stock file back byte-identical (md5-checked), the converter removed, the `persist.leafia.*`
  switches cleared, our state removed. Restart the head unit.
- **/system is never made read-only.** dalvik-cache entries that root cannot remove (adb's root has no capabilities)
  are only logged: Dalvik rebuilds a stale entry at boot, and a stock apk runs from its odex.

Log: `/data/nemesis/jmk-autoplay-hud.log`. By hand: `sh /data/nemesis/apps/jmk-autoplay-hud/bin/status.sh`.

## Status contract (for the JMK MAP menu's root daemon)

`/data/nemesis/jmk-autoplay-hud/status`, `key=value` lines:

| key | values |
|---|---|
| `ver` | package version |
| `state` | `locked` (nothing changed, see `reason`) · `reboot` (patched, restart needed) · `active` (a later boot found every patched file in place) · `failed` (see `reason`) |
| `set` | patch set (`neev_kr`, ...) or empty |
| `patched` | what is patched now: `gpm,navi,lib,iap2,dipo,pp,audio,core,utils,conv` (those that apply) |
| `reason` | one line, why locked / failed |
| `knobs` | the menu config keys this set's builds read (the menu hides the others) |
| `warn` | e.g. dalvik-cache entries left |

## Settings bridge

The settings service (`svc/hud.sh`, NEMESIS `[service]`) reads `/data/local/tmp/jmk-autoplay-hud/config` (written by
the MAP menu's daemon) at start and whenever it changes (checked every 5 s), and sets the switches the patched apps
read. Missing or invalid values give Leafia r8's defaults.

| config key | switch | values | read by (neev_kr) |
|---|---|---|---|
| `log` | `persist.leafia.log`, `persist.leafia.lane.log` | 1 → `1`, 0 → `0` (default 1) | HKMC_GPM, HKMC_Navi_ExSL, HKMC_DiPO (bridge), Iap2ServerApp (bridge) |
| `lane_dist` | `persist.leafia.lane.dist` | 1 → `label`, 0 → `off` (default label) | HKMC_GPM, HKMC_Navi_ExSL, HKMC_DiPO (bridge) |
| `cp_lanes` | `persist.leafia.cp.lanes` | 1 → `1`, 0 → `0` (default 1) | Iap2ServerApp (bridge) |

Every other key of the menu (on_cluster, on_hud, phones, look, ar_dist, ar_speed, unknown_turn, roundabout, bar,
bar_ref, dist_round, lanes, road_name, dest_name, hud_road, aa_name_hold, hud_next, hud_junction, hud_lanes,
reroute_text, idle_clear_min, app_change_restart) has no switch in these builds. The other sets' builds read none of
these switches. Leafia's retired or not-shipped switches (lane.src/hl/mode/gauge/dim/gate, turn.split, tbt.standard,
owner.r4bridge, delete.aa) are cleared when set, so the apps run with their defaults.

## Build and test (Mac)

    python3 build_nemesis_package.py                  # dist/jmk-autoplay-hud-<v>.zip (all sets)
    python3 build_nemesis_package.py --sets neev_kr   # dist/jmk-autoplay-hud-<v>-kr.zip (small, for the car link)
    bash test/scripts-test.sh                         # the hooks in a fake root (lpatch, dexopt, pm stubbed)
    bash test/check-scripts.sh                        # syntax (mksh if present, else bash/sh/ksh), banned commands, patch data

Test zips stay in `dist/` (never `dist/release`, never the public repo).
