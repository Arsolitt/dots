#!/bin/sh
# Suspend workaround for the bitland_mifs_wmi kernel driver.
#
# The in-tree driver (kernel 7.3.1) has a suspend callback that returns
# -EINVAL and aborts every system suspend; the fix (upstream commit
# d3666875c75e) is not in 7.3.1 yet. Unbinding the WMI control device
# before sleep and rebinding it after resume lets suspend succeed. Drop
# this once a fixed kernel ships.
set -eu

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

HOOK=/etc/systemd/system-sleep/bitland-mifs-wmi.sh

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
}

hook_body() {
    cat <<'HOOK_BODY'
#!/bin/sh
# Installed by dots suspend/bitland-sleep.sh: the bitland_mifs_wmi suspend
# callback returns -EINVAL on kernel 7.3.1 and aborts sleep, so the control
# device is unbound before suspend and rebound after resume.
DEV=B60BFB48-3E5B-49E4-A0E9-8CFFE1B3434B-4
CTRL=/sys/bus/wmi/drivers/bitland-mifs-wmi
case ${1:-} in
    pre) echo "$DEV" >"$CTRL/unbind" 2>/dev/null || true ;;
    post) echo "$DEV" >"$CTRL/bind" 2>/dev/null || true ;;
esac
HOOK_BODY
}

cmd_status() {
    if [ -f "$HOOK" ]; then
        printf 'hook installed: %s\n' "$HOOK"
    else
        printf 'hook absent: %s\n' "$HOOK"
    fi
    if [ -d /sys/bus/wmi/drivers/bitland-mifs-wmi ]; then
        printf 'driver present: bitland-mifs-wmi\n'
    else
        printf 'driver absent: bitland-mifs-wmi\n'
    fi
}

cmd_check() {
    [ -f "$HOOK" ] || return 1
    _tmp=$(mktemp) || return 1
    hook_body >"$_tmp"
    if cmp -s "$_tmp" "$HOOK"; then
        rm -f "$_tmp"
        return 0
    fi
    rm -f "$_tmp"
    return 1
}

cmd_install() {
    require_root
    _tmp=$(mktemp)
    hook_body >"$_tmp"
    if [ -f "$HOOK" ] && cmp -s "$_tmp" "$HOOK"; then
        printf 'unchanged %s\n' "$HOOK"
    else
        install -D -m 0755 "$_tmp" "$HOOK"
        printf 'installed %s\n' "$HOOK"
    fi
    rm -f "$_tmp"
}

cmd_uninstall() {
    require_root
    if [ -f "$HOOK" ]; then
        rm -f "$HOOK"
        printf 'removed %s\n' "$HOOK"
    else
        printf 'already absent: %s\n' "$HOOK"
    fi
}

case ${1:-status} in
    status) cmd_status ;;
    check) cmd_check ;;
    install) cmd_install ;;
    uninstall) cmd_uninstall ;;
    *) die "usage: bitland-sleep {status|check|install|uninstall}" ;;
esac
