# jmk-autoplay-hud (LivePatch build): the status file the JMK MAP menu's daemon reads (AGPL-3.0, see LICENSE and NOTICE.md). Sourced after lp-common.sh and lp-settings.sh.
# ver= state=locked|reboot|active|failed set=<profile> patched=<tags> reason= knobs=<config keys with a switch> warn= converter=needed|native|unknown
# Nothing is compared with records any more: LivePatch holds the files, `nemesis livepatch status` says which targets are mounted.
STATUS=$STORE/status
BOOT_FILE=$STORE/boot                  # the boot that ran the install (state=reboot until another boot)
SAFE=0
boot_token() {
    local b
    b=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
    [ -n "$b" ] || b=$(getprop ro.runtime.firstboot)
    echo "$b"
}
tag_of() {
    case "$1" in
        HKMC_GPM) echo gpm ;; HKMC_DiPO) echo dipo ;; Iap2ServerApp) echo iap2 ;; HKMC_Navi_ExSL) echo navi ;;
        PhoneProjection) echo pp ;; libautoreceiver_infobank.so) echo lib ;; libCarPlayAudio.so) echo audio ;;
        libCarPlayCore.so) echo core ;; libiap2session.so) echo iap2s ;; *) echo "$1" ;;
    esac
}
# lp_profile: "profile=<p> parts=<..> apps=<a,b> libs=<l>" from the tool (the same choice every step makes), exit 10 = no profile fits
lp_profile() { sh "$PKG/tools/hud-step" profile 2>/dev/null; }
pv() {   # pv <key> <profile line>
    local w; for w in $2; do case "$w" in "$1="*) echo "${w#*=}"; return 0 ;; esac; done; return 1
}
# target_state <path>: mounted | unmounted | none, from `nemesis livepatch status` ([ASSUMED] one line per target with the word mounted, farmed or unmounted)
LPST=
target_state() {
    local l
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in *"$1"*) case "$l" in *unmounted*) echo unmounted; return 0 ;; *mounted*|*farmed*) echo mounted; return 0 ;; esac ;; esac
    done <<EOT
$LPST
EOT
    echo none
}
write_status() {   # write_status <state> <reason> [warn]
    local tmp=$STATUS.tmp conv
    mkdir -p "$STORE" 2>/dev/null
    conv=$(sh "$PKG/scripts/converter-check.sh" 2>/dev/null)
    conv=${conv#converter=}; conv=${conv%% *}
    {
        echo "ver=$VER"; echo "state=$1"; echo "set=$PROFILE"; echo "patched=$PATCHED"; echo "reason=$2"
        echo "knobs=$KNOBS"; echo "warn=$3"; echo "converter=${conv:-unknown}"
    } > "$tmp" 2>/dev/null || return 1
    chmod 0644 "$tmp"
    mv "$tmp" "$STATUS"
}
# decide: sets STATE REASON PROFILE PATCHED KNOBS from the tool's profile and LivePatch's own status
STATE=; REASON=; PROFILE=; PATCHED=; KNOBS=
decide() {
    local prof rc a l apps libs miss= unm= t k
    STATE=; REASON=; PROFILE=; PATCHED=; KNOBS=
    LPST=$("$NEMESIS_BIN" livepatch status 2>/dev/null)
    case "$LPST" in *safe=1*) SAFE=1; STATE=failed; REASON="NEMESIS LivePatch safe mode is on: the stock files are shown"; return 0 ;; esac
    SAFE=0
    prof=$(lp_profile); rc=$?
    PROFILE=$(pv profile "$prof")
    if [ $rc -ne 0 ] || [ -z "$PROFILE" ] || [ "$PROFILE" = none ]; then
        case "$prof" in *"could not be read"*) PROFILE=; STATE=failed; REASON="the stock files could not be read (nemesis livepatch stock failed): the firmware was not judged"; return 0 ;; esac
        PROFILE=; STATE=locked; REASON="no patch for this firmware: its stock code is in no profile"; return 0
    fi
    for k in $(knob_keys "$PROFILE"); do KNOBS="$KNOBS,$k"; done; KNOBS=${KNOBS#,}
    if [ -z "$LPST" ]; then STATE=failed; REASON="nemesis livepatch status gave nothing"; return 0; fi
    apps=$(pv apps "$prof"); libs=$(pv libs "$prof")
    IFS=,; set -- $apps; IFS=" 	
"
    for a in "$@"; do
        case "$(target_state "/system/app/$a.odex")" in
            mounted) PATCHED="$PATCHED,$(tag_of "$a")" ;;
            unmounted) unm="$unm $a" ;;
            *) miss="$miss $a" ;;
        esac
    done
    IFS=,; set -- $libs; IFS=" 	
"
    for a in "$@"; do [ "$(target_state "/system/lib/$a")" = mounted ] && PATCHED="$PATCHED,$(tag_of "$a")"; done
    for a in libCarPlayCore.so libCarPlayAudio.so libiap2session.so; do [ "$(target_state "/system/lib/$a")" = mounted ] && PATCHED="$PATCHED,$(tag_of "$a")"; done
    PATCHED=${PATCHED#,}
    if [ -n "$unm" ]; then STATE=failed; REASON="LivePatch took these down at boot (the firmware changed?):$unm"; return 0; fi
    if [ -n "$miss" ]; then
        if [ -f "$BOOT_FILE" ] && [ "$(boot_token)" = "$(cat "$BOOT_FILE" 2>/dev/null)" ]; then STATE=reboot; REASON=""; else STATE=failed; REASON="not mounted after the reboot:$miss"; fi
        return 0
    fi
    STATE=active; REASON=""
}
