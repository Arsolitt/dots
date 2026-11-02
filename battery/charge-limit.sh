#!/bin/sh
# RedmiBook 2026 battery charge limit through the firmware WMI method WMAA.
#
# WMAA(Arg0, Arg1, Arg2): Arg1 must be 1, Arg0 is ignored, Arg2 is a 32-byte buffer
#   word  0x00  FUN1  0xfa00 read / 0xfb00 write
#   word  0x02  FUN2  0x1000 battery
#   word  0x04  FUN3  0x0002 charge limit
#   dword 0x06  FUN4  limit code: 0 off, 1 80%, 4 90%, 5 70%, 6 60%, 7 50%, 8 40%
# The reply is the RETS buffer: SGER word, FUTR word, FRD0 word, FRD1 dword.
# The EC mirrors the state in LONL (0xa4, bit 0) and HBDA (0xa7: 0x50, 0x5a, 0x46, 0x3c, 0x32, 0x28).
set -eu

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

CALL=/proc/acpi/call
SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")
BIN=/usr/local/sbin/charge-limit
UNIT=/etc/systemd/system/battery-charge-limit.service
RULE=/etc/udev/rules.d/99-battery-charge-limit.rules
MODCONF=/etc/modules-load.d/acpi_call.conf

PATHS='\_SB.PC00.WMID.WMAA \_SB.PCI0.WMID.WMAA'
ARGV='0x1 0x1'
BUFSIZE=32
CODE80=1

die() {
    printf 'charge-limit: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
}

wmaa_buf() {
    printf '{0x00,0x%s,0x00,0x10,0x%02x,0x00,0x%02x,0x00' "$1" "$2" "$3"
    i=8
    while [ "$i" -lt "$BUFSIZE" ]; do
        printf ',0x00'
        i=$((i + 1))
    done
    printf '}'
}

wmaa_call() {
    printf '%s %s %s\n' "$_path" "$ARGV" "$(wmaa_buf "$1" "$2" "$3")" >"$CALL"
    tr -d '\000' <"$CALL"
}

load_module() {
    [ -e "$CALL" ] && return 0
    modprobe acpi_call 2>/dev/null || true
    [ -e "$CALL" ]
}

select_channel() {
    load_module || die "cannot load acpi_call; install acpi_call-dkms"
    for _path in $PATHS; do
        case $(wmaa_call fa 02 00) in
            '{'*) return 0 ;;
        esac
    done
    die "WMAA 0x1000/2 is not available on this firmware"
}

decode_response() {
    case ${1:-} in
        '{'*) ;;
        *) return 1 ;;
    esac
    set -- $(printf '%s' "$1" | tr -d '{}' | tr ',' ' ')
    [ "$#" -ge 10 ] || return 1
    SGER=$(( $1 | ($2 << 8) ))
    FUTR=$(( $3 | ($4 << 8) ))
    FRD0=$(( $5 | ($6 << 8) ))
    FRD1=$(( $7 | ($8 << 8) | ($9 << 16) | (${10} << 24) ))
}

code_to_percent() {
    case $1 in
        1) printf '80' ;;
        4) printf '90' ;;
        5) printf '70' ;;
        6) printf '60' ;;
        7) printf '50' ;;
        8) printf '40' ;;
        *) printf '0' ;;
    esac
}

read_limit() {
    _r=$(wmaa_call fa 02 00)
    decode_response "$_r" || die "unexpected WMAA reply: $_r"
    [ "$SGER" -eq 32768 ] || die "firmware refused the read: SGER=$(printf '0x%04x' "$SGER")"
    [ "$FRD0" -eq 2 ] || die "firmware answered subcommand $(printf '0x%02x' "$FRD0"), not the charge limit"
}

battery_state() {
    for _p in /sys/class/power_supply/BAT*; do
        [ -r "$_p/capacity" ] || continue
        printf 'battery %s: %s%% %s\n' "$(basename "$_p")" \
            "$(cat "$_p/capacity")" "$(cat "$_p/status")"
    done
    for _p in /sys/class/power_supply/*; do
        [ -r "$_p/type" ] || continue
        [ "$(cat "$_p/type")" = Mains ] || continue
        printf 'adapter %s: online=%s\n' "$(basename "$_p")" "$(cat "$_p/online")"
    done
}

show_state() {
    if [ "$FRD1" -eq 0 ]; then
        printf 'limit: off, FRD1=0x%08x\n' "$FRD1"
    else
        printf 'limit: %s%% (code %s), FRD1=0x%08x\n' \
            "$(code_to_percent "$FRD1")" "$FRD1" "$FRD1"
    fi
}

cmd_status() {
    require_root
    select_channel
    read_limit
    show_state
    battery_state
}

cmd_probe() {
    require_root
    load_module || die "cannot load acpi_call; install acpi_call-dkms"
    printf 'acpi_call: loaded (%s)\n' "$CALL"
    for _path in $PATHS; do
        printf 'try %s -> %s\n' "$_path" "$(wmaa_call fa 02 00)"
    done
    _path=${PATHS%% *}
    _r=$(wmaa_call fa 02 00)
    if decode_response "$_r"; then
        printf 'decoded: SGER=0x%04x FRD0=0x%04x FRD1=0x%08x (%s%%)\n' \
            "$SGER" "$FRD0" "$FRD1" "$(code_to_percent "$FRD1")"
    fi
    battery_state
}

cmd_on() {
    require_root
    select_channel
    wmaa_call fb 02 "$CODE80" >/dev/null
    sleep 1
    read_limit
    [ "$FRD1" -eq "$CODE80" ] || die "the firmware did not accept the 80% limit (FRD1=$FRD1)"
    show_state
}

cmd_off() {
    require_root
    select_channel
    wmaa_call fb 02 00 >/dev/null
    sleep 1
    read_limit
    [ "$FRD1" -eq 0 ] || die "the firmware did not clear the limit (FRD1=$FRD1)"
    show_state
}

ec_byte() {
    dd if=/sys/kernel/debug/ec/ec0/io bs=1 skip="$1" count=1 2>/dev/null |
        od -An -tu1 | tr -d ' \n'
}

cmd_ec() {
    require_root
    modprobe ec_sys 2>/dev/null || true
    [ -e /sys/kernel/debug/ec/ec0/io ] || die "ec_sys does not expose the EC (debugfs missing?)"
    _lonl=$(ec_byte 164) || die "cannot read EC 0xa4"
    _afbc=$(ec_byte 165) || die "cannot read EC 0xa5"
    _hbda=$(ec_byte 167) || die "cannot read EC 0xa7"
    [ -n "$_lonl" ] && [ -n "$_afbc" ] && [ -n "$_hbda" ] || die "EC read returned nothing"
    printf 'EC 0xa4 LONL = 0x%02x (bit0 = %s)\n' "$_lonl" "$((_lonl & 1))"
    printf 'EC 0xa5 AFBC = 0x%02x\n' "$_afbc"
    printf 'EC 0xa7 HBDA = 0x%02x\n' "$_hbda"
}

cmd_install() {
    require_root
    [ "$HERE" != /usr/local/sbin ] || die "run install from the repository checkout"
    modinfo acpi_call >/dev/null 2>&1 ||
        die "acpi_call module is missing: sudo pacman -S --needed acpi_call-dkms"
    select_channel
    install -Dm755 "$SELF" "$BIN"
    install -Dm644 "$HERE/battery-charge-limit.service" "$UNIT"
    install -Dm644 "$HERE/99-battery-charge-limit.rules" "$RULE"
    printf 'acpi_call\n' >"$MODCONF"
    systemctl daemon-reload
    udevadm control --reload-rules
    systemctl enable battery-charge-limit.service >/dev/null 2>&1
    systemctl restart battery-charge-limit.service
    sleep 2
    systemctl --no-pager --lines=0 status battery-charge-limit.service || true
    cmd_status
}

cmd_uninstall() {
    require_root
    systemctl disable --now battery-charge-limit.service >/dev/null 2>&1 || true
    rm -f "$UNIT" "$RULE" "$MODCONF" "$BIN"
    systemctl daemon-reload
    udevadm control --reload-rules
    printf 'removed %s, %s, %s, %s\n' "$UNIT" "$RULE" "$MODCONF" "$BIN"
}

case ${1:-status} in
    status) cmd_status ;;
    on | enable) cmd_on ;;
    off | disable) cmd_off ;;
    probe) cmd_probe ;;
    ec) cmd_ec ;;
    install) cmd_install ;;
    uninstall) cmd_uninstall ;;
    *) die "usage: charge-limit {status|on|off|probe|ec|install|uninstall}" ;;
esac
