# jmk-autoplay-hud: JMK AutoPlay 확장 (HUD · 계기판 길안내)

An add-on NEMESIS package for Korean Gen5W head units (developed on a 2023 Ioniq 5, NEEV.KOR 260902). It sits on top of
JMK Wireless AutoPlay (`jmk-autoplay`, which turns the stock wireless features on) and gives the car two things:

- **Android Auto and CarPlay turn-by-turn on the stock cluster and HUD** (direction pictures, distance, the near-turn
  bar, road and destination names, lanes, remaining distance and arrival time).
- **The CarPlay Bluetooth bridge** that wireless CarPlay needs on the Korean firmware, with now-playing and call state.

**Licence: AGPL-3.0** (`LICENSE`). Nothing in this package is obfuscated. No code of it goes into any other JMK package,
and none of theirs into it. Source: https://github.com/JMK-labs/jmk-autoplay-hud.

## Where it comes from

A fork of the NEMESIS community package `projection.tbt` and HMG Leafia Plus (GPL-3.0: bridge, recipes, `lpatch`), with
rules ported and adapted from an AGPL-3.0 Korean-firmware mod code base for the near-turn behaviour, the cluster distance
bar and the Korean turn pictures. The full list of upstream projects, versions, licences and what was taken from each is
in `NOTICE.md`; every ported source file carries its own header. The per-car patch data, the install journal, the
tamper-safe restore, the settings bridge and the MAP menu side are JMK's own.

## What it supports

| | Android Auto | CarPlay |
|---|---|---|
| Turn picture on the cluster and HUD (stock Korean numbers, ramps, forks, expressway in / exit) | yes | yes |
| Distance, road name, destination, remaining distance, arrival time | yes | yes |
| Near-turn big picture and distance bar (350 m, 1050 m on an expressway) | yes | yes |
| Lanes as the phone shows them (white, blue for the lane to use, grey) | where the app sends them | yes |
| Guidance clears at once when the phone disconnects or the session ends | yes | yes |
| Bridge for wireless CarPlay, now playing and call state | | yes |

Cars (by `ro.build.product`, each target rebuilt from its own stock file only when that file has the exact stock md5):

| Group | Cars |
|---|---|
| Hyundai Ioniq 5 Korea | NEEV.KOR 260902 (turn-by-turn and bridge); older V037 firmware (turn-by-turn) |
| Hyundai | Ioniq 6, Sonata DN8 / DN8 Hybrid, Santa Fe TM facelift, Avante and Avante N facelift, Avante Hybrid, Tucson and Tucson Hybrid, Palisade LX2, Genesis G70 facelift |
| Kia | EV6 Korea, K5 / K5 Hybrid, K7 Premier, K8 / K8 Hybrid, Seltos, Sorento / Sorento Hybrid, Stinger, Niro Hybrid, Mohave, Soul EV, Carnival KA4 (older firmware, turn-by-turn), Sportage Hybrid NQ5HEV (older firmware V038, turn-by-turn) |
| Other markets | Ioniq 5 US / Canada, EV6 US / Canada, Kia Sportage (US) |

**Car-tested** (by us or reported by owners): the Ioniq 5 Korea NEEV.KOR 260902 (our development car) and the cars owners
have confirmed in their reports. Everything else in the table is built from that car's own stock files and checked on the
Mac against them (md5, patch, dexopt); it is **not car-tested** until an owner reports it. The release notes in git
history say which build was driven. A car whose files are not exactly a known stock set is left unchanged
(`state=locked`, with the reason in the status).

## Releases (results)

- **0.3.1**: Installs through NEMESIS 1.17 LivePatch: no file in /system is edited.
- **0.2.6**: Wireless CarPlay keeps the phone's Bluetooth connected.
- **0.2.5**: HUD DiPO bridge: a local JMK service (`jmk.core`) decides how the route display proceeds.
- **0.2.3**: 업데이트할 때 바뀌는 순정 앱만 다시 시작합니다.
- **0.2.2**: 안드로이드 오토 길안내가 직진 구간에서 꺼졌다 켜졌다 하지 않습니다. 계기판으로 넘기는 안내 문구의 길이를 기록합니다(문구 내용은 기록하지 않습니다).
- **0.2.1**: no change in behaviour (internal cleanup).
- **0.2.0**: HUD DiPO bridge: at the point where Leafia starts the car hotspot it asks a local JMK service (`jmk.core`) first and skips its own start when the service answers that it should (the hotspot is already on or being started, or the car's settings keep it off) — readable in the public HUD source.
- **0.1.38**: 펌웨어를 업데이트한 차에서 삭제 · 업데이트할 때 순정 파일을 예전 것으로 되돌리지 않습니다. 스포티지 하이브리드(이전 펌웨어 V038)에서 계기판 · HUD 길안내가 설치됩니다.
  Technical: an `.odex` now counts as ours only by its own md5 (the made list) once the firmware fingerprint differs from the one recorded at install,
  so an uninstall, an update or the integrity lock never writes the old firmware's stock odex over a new one (the file is left as it is and reported).
  New by-code profile `krq`: Kia Sportage Hybrid Korea NQ5HEV V038 (260604), turn-by-turn only. Its GPM, DiPO and Navigation code is the
  Ioniq 5's with other ProGuard names, so each result is the Ioniq 5's build; no bridge and no library part (their files were not available to prove them).
- **0.1.37**: 카플레이 영상이 잠깐 끊겨도 연결이 유지됩니다.
  Technical: on the stock `libCarPlayCore.so` md5 ef49c09b (the Korean Ioniq 5 260902 build) `recipes/carplay-core-frames-ef49c09b.recipe`
  (from the Open-HMG wireless CarPlay + Android Auto mod, AGPL-3.0) lets `ProcessFrames` wait 10 s for a video frame instead of
  about 200 ms, so a short Wi-Fi stall no longer ends the stream. Five bytes of the file change; any other build of the file is
  left alone (the whole-file md5 is checked first), and uninstall puts the stock file back.
- **0.1.36**: 길안내만 설치된 차종에서도 카플레이 고속도로 진입 · 출구 그림이 순정 내비처럼 표시됩니다.
  Technical: the turn-by-turn-only DiPO results (no bridge part) carried the CarPlay far-icon table of the Korean-firmware mod
  code base with its US numbers. `src/tbt/cpstock.sh` puts eleven constants of that table back to the car's own stock values
  (on-ramp 172 to 160, expressway exit 82 / 81 to 165 / 164, the eight left-hand roundabout rows 96..107 to 192..203) and
  changes nothing else: no hook, no class, no log line. The bridge, Android Auto and Navigation results are 0.1.34's.
- **0.1.35**: no change in behaviour. Documentation and source headers now describe the AGPL-3.0 Korean-firmware mod code base in neutral words. The patched files are byte-identical to 0.1.34.
- **0.1.34**: highway entry / exit, fork and ramp pictures look like the stock navigation.
- **0.1.33**: the near-turn distance bar of the phone's guidance shows on the cluster like the stock one.
- **0.1.32 / 0.1.28 / 0.1.20 / 0.1.12 / 0.1.10 / 0.1.7**: the wireless CarPlay bridge and guidance reach more cars
  (Kia K5 / Sorento / K7 / Stinger / Mohave / Seltos / Soul EV / Niro, Hyundai Avante / Tucson / Santa Fe / Sonata /
  Palisade, Ioniq 6, EV6, G70) when their framework files match a verified set.
- **0.1.31 / 0.1.27 / 0.1.26 / 0.1.25 / 0.1.24 / 0.1.23**: installs and updates finish on every car, also after a full
  remove and reinstall or an interrupted install; every stock copy is archived by md5 and restored byte for byte.
- **0.1.30**: CarPlay lane guidance is drawn as on the phone, on the cluster and the HUD.
- **0.1.22 / 0.1.21**: wireless CarPlay starts for an iPhone whose Bluetooth data has not arrived yet; the CarPlay screen
  stabiliser of Wireless AutoPlay applies on the Ioniq 5 and the Korean profiles.
- **0.1.19**: guidance disappears at once when Android Auto or CarPlay drops or ends.
- **0.1.18 / 0.1.13**: wireless CarPlay now playing and call state keep updating.
- **0.1.16 / 0.1.14**: turn-by-turn on the older Korean firmware (V035 / V037).
- **0.1.11**: the near-turn picture no longer flips at the window edge, and the next turn's picture no longer flashes
  when a map app sends a new maneuver with the old distance.

Test commands and rebuild scripts for each of these are under `test/` and `src/tbt/`; the exact stock file hashes and
patch-set lines are in `package/patches/` (`cars`, `bycode/*/manifest`).

## Install, update, uninstall

- **preinstall**: a first install needs `jmk-autoplay` installed and refuses next to another phone-projection package
  (Leafia, the upstream NEMESIS projection packages, Evergreen, 단풍, another Korean-firmware wireless mod, aa.usbwifi, an HMG-API mod).
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

## Status interface (for the JMK MAP menu's root daemon)

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

0.1.19: "계기판 길안내 지우기" is `am broadcast -a com.jmk.hud.TBT_CLEAR` from the root daemon (no extras; both patched
apps answer it once their service has started, so a version or set without our GPM / DiPO build simply ignores it).

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
