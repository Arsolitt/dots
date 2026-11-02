#!/bin/sh
# Keep power-profiles-daemon off the broken ACPI platform_profile interface.
#
# bitland-mifs-wmi (Xiaomi REDMI Book Pro 16 2026) refuses performance and
# balanced-performance unless the firmware reports the round DC jack, and the
# laptop is USB-C only. The rejection aborts the whole write to the aggregate
# /sys/firmware/acpi/platform_profile, so power-profiles-daemon can never leave
# balanced; its handler also fails to read the mode back, which leaves the
# aggregate permanently "custom".
#
# Blocking ppd's platform_profile driver leaves the intel_pstate CPU driver,
# which writes energy_performance_preference and works. The Xiaomi EC
# fan/thermal mode stays out of reach until the kernel gains the upstream fix
# ("performance profiles unreachable on USB-C-only models"); drop the drop-in
# once that lands.
set -eu

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")
SOURCE=$HERE/10-cpu-only.conf
DROPIN=/etc/systemd/system/power-profiles-daemon.service.d/10-cpu-only.conf
UNIT=power-profiles-daemon.service

die() {
    printf 'ppd-platform-driver: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
}

current_exec() {
    systemctl show -p ExecStart --value "$UNIT" 2>/dev/null || printf 'unknown'
}

profile_line() {
    powerprofilesctl get 2>/dev/null || printf 'unknown'
}

epp_lines() {
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -r "$_policy/energy_performance_preference" ] || continue
        printf 'epp %s: %s\n' "$(basename "$_policy")" \
            "$(cat "$_policy/energy_performance_preference")"
    done
}

cmd_status() {
    if [ -f "$DROPIN" ]; then
        printf 'drop-in: %s\n' "$DROPIN"
        if cmp -s "$SOURCE" "$DROPIN"; then
            printf 'content: matches the repository\n'
        else
            printf 'content: differs from the repository (re-run install)\n'
        fi
    else
        printf 'drop-in: absent, ppd drives the ACPI platform_profile interface\n'
    fi
    printf 'exec: %s\n' "$(current_exec)"
    printf 'profile: %s\n' "$(profile_line)"
    epp_lines
    if [ -r /sys/firmware/acpi/platform_profile ]; then
        printf 'acpi aggregate: %s\n' \
            "$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || printf 'unreadable')"
    fi
}

cmd_install() {
    require_root
    [ -f "$SOURCE" ] || die "missing $SOURCE; run install from the repository checkout"
    _changed=0
    if cmp -s "$SOURCE" "$DROPIN"; then
        printf 'unchanged %s\n' "$DROPIN"
    else
        install -Dm644 "$SOURCE" "$DROPIN"
        printf 'installed %s\n' "$DROPIN"
        _changed=1
    fi
    if [ "$_changed" -eq 1 ]; then
        systemctl daemon-reload
        systemctl restart "$UNIT"
    elif ! systemctl is-active --quiet "$UNIT"; then
        systemctl start "$UNIT"
    fi
    case $(current_exec) in
        *--block-driver=platform_profile*) ;;
        *) die "ppd runs without the drop-in; check systemctl status $UNIT" ;;
    esac
    printf 'ok: platform_profile blocked, profiles are served by the CPU driver\n'
}

cmd_uninstall() {
    require_root
    if [ -f "$DROPIN" ]; then
        rm -f "$DROPIN"
        rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
        printf 'removed %s\n' "$DROPIN"
    else
        printf 'already absent: %s\n' "$DROPIN"
    fi
    systemctl daemon-reload
    systemctl try-restart "$UNIT"
}

case ${1:-status} in
    status) cmd_status ;;
    install) cmd_install ;;
    uninstall) cmd_uninstall ;;
    *) die "usage: ppd-platform-driver {status|install|uninstall}" ;;
esac
