#!/system/bin/sh
# Installs through NEMESIS 1.17 LivePatch: no file in /system is edited.
# jmk-autoplay-hud preinstall (LivePatch build; AGPL-3.0, see LICENSE and NOTICE.md). Refuses, with a one-line reason NEMESIS shows:
#  1. a firmware that still needs the converter (libev6aac.so): the LivePatch HUD does not ship it; the car stays on the legacy HUD
#     until a firmware update makes the converter state NATIVE (report "install: needs-converter"; the same check is scripts/converter-check.sh)
#  2. NEMESIS older than 1.17, or its LivePatch wrapper not active / safe mode on (when `nemesis livepatch status` says so)
#  3. JMK Wireless AutoPlay missing, or another phone-projection package next to us
. ./scripts/lp-common.sh
log "preinstall $ID $VER (LivePatch)"
out=$(sh "$PKG/scripts/converter-check.sh" 2>&1); rc=$?
log "converter check: $out (exit $rc)"
case $rc in
    0) ;;
    11) log "FAIL: 이 펌웨어는 변환 라이브러리(libev6aac.so)가 필요합니다. 펌웨어를 업데이트하면 이 버전을 설치할 수 있습니다 (this firmware still needs the converter: install the legacy HUD, or update the firmware first)"
        report needs-converter "$out"; exit 1 ;;
    *)  log "FAIL: 변환 라이브러리 필요 여부를 확인하지 못했습니다 (could not check the converter state)"
        report converter-check-failed "$out"; exit 1 ;;
esac
v=$("$NEMESIS_BIN" version 2>/dev/null); v=${v%%
*}
vn=$v; while [ -n "$vn" ]; do case "$vn" in [0-9]*) break ;; esac; vn=${vn#?}; done; vn=${vn%%[!0-9.]*}
oldifs=$IFS; IFS=.; set -- $vn; IFS=$oldifs
case "$1$2" in *[!0-9]*) set -- ;; esac
if [ -n "$1" ] && { [ "$1" -lt 1 ] || { [ "$1" -eq 1 ] && [ "${2:-0}" -lt 17 ]; }; }; then
    log "FAIL: NEMESIS $v is older than 1.17 (NEMESIS 1.17 이상이 필요합니다)"; report nemesis-too-old "$v"; exit 1
fi
[ -n "$1" ] || log "NEMESIS version not readable ($v): not refused by version"
st=$("$NEMESIS_BIN" livepatch status 2>/dev/null)
case "$st" in *wrapper=0*) log "FAIL: the NEMESIS LivePatch wrapper is not active"; report lp-wrapper-off "$st"; exit 1 ;; esac
case "$st" in *safe=1*) log "FAIL: NEMESIS LivePatch safe mode is on: turn it off and reboot first"; report lp-safe-on "$st"; exit 1 ;; esac
if ! pkg_installed jmk-autoplay; then
    log "FAIL: JMK Wireless AutoPlay(jmk-autoplay)를 먼저 설치하세요 (install jmk-autoplay first)"; report preinstall-no-autoplay "jmk-autoplay is not installed"; exit 1
fi
if other=$(other_projection); then
    log "FAIL: another phone-projection package is installed: $other. Uninstall it and reboot first (다른 프로젝션 프로그램이 설치되어 있습니다)"
    report preinstall-other-projection "$other"; exit 1
fi
exit 0
