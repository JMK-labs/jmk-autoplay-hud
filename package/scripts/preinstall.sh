#!/system/bin/sh
# jmk-autoplay-hud preinstall (AGPL-3.0, see LICENSE and NOTICE.md). A first install needs JMK Wireless AutoPlay (it
# turns the stock wireless features on; this add-on only adds the turn-by-turn) and refuses next to another
# phone-projection package, which would change the same stock apps. An update always goes ahead: the old
# preuninstall has run already, and a refusal would leave the car without the package.
. ./scripts/common.sh
log "preinstall $ID $VER"
if [ ! -f "$INSTALLED" ]; then
    if ! pkg_installed jmk-autoplay; then
        log "FAIL: JMK Wireless AutoPlay(jmk-autoplay)를 먼저 설치하세요 (install jmk-autoplay first)"
        report preinstall-no-autoplay "jmk-autoplay is not installed"
        exit 1
    fi
    if other=$(other_projection); then
        log "FAIL: another phone-projection package is installed: $other. Uninstall it and reboot first (다른 프로젝션 프로그램이 설치되어 있습니다)"
        report preinstall-other-projection "$other"
        exit 1
    fi
fi
exit 0
