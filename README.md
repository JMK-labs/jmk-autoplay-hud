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
| `dl3hev` | Kia K5 Hybrid Korea | as `neev`; patches/cars has no line for it (as Leafia's Korean port ships it): reached only when its stock files all match |

Plus the CarPlay library recipes, each checked on its own file: `carplay-utils-converter` (libCarPlayUtils.so, with
`libev6aac.so`), `carplay-audio-formats` (libCarPlayAudio.so: AAC music, Opus voice over Wi-Fi) and
`carplay-core-wifi` (libCarPlayCore.so). On NEEV.KOR 260902 only the audio one applies (the other two are NATIVE).
`os="*.KOR.*"` in NEMESIS.data limits installs to KOR firmware; the other sets are kept for other models.

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
