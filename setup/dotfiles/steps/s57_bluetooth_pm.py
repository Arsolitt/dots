"""Bluetooth: keep the RTL8761BU dongle awake with a udev rule."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .. import detect
from ..cli import Context
from . import Step

RULE = Path("/etc/udev/rules.d/99-rtl8761bu-bt.rules")
ARTIFACT = "udev/99-rtl8761bu-bt.rules"


def _backup_name(target: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return target.with_name(f"{target.name}.dots-backup-{stamp}")


def _deploy_rule(ctx: Context) -> None:
    artifact = ctx.root / ARTIFACT
    if not artifact.is_file():
        ctx.log_err(f"bluetooth_pm: missing {artifact}")
        return

    desired = artifact.read_text(encoding="utf-8")
    try:
        current = RULE.read_text(encoding="utf-8")
    except OSError:
        current = None

    if current == desired:
        ctx.log_skip(f"bluetooth_pm: {RULE} already matches the repo artifact")
        return

    backup = _backup_name(RULE)
    if ctx.dry_run:
        if current is not None:
            ctx.log_info(f"would backup {RULE} -> {backup}")
        ctx.log_info(f"would install {artifact} -> {RULE}")
        return

    if current is not None:
        ctx.run(["cp", "-p", str(RULE), str(backup)], sudo=True)
    ctx.run(["install", "-m", "0644", str(artifact), str(RULE)], sudo=True)


def _run(ctx: Context) -> None:
    _deploy_rule(ctx)
    if detect.rtl8761bu_pm_control() == "on":
        ctx.log_skip("bluetooth_pm: dongle runtime PM already disabled")
        return
    if not ctx.have("udevadm"):
        ctx.log_warn("bluetooth_pm: udevadm not available — replug the dongle to apply the rule")
        return
    ctx.run(["udevadm", "control", "--reload"], sudo=True)
    ctx.run(
        [
            "udevadm", "trigger",
            "--attr-match=idVendor", detect.RTL8761BU_VENDOR,
            "--attr-match=idProduct", detect.RTL8761BU_PRODUCT,
        ],
        sudo=True,
    )
    if ctx.dry_run:
        return
    if detect.rtl8761bu_pm_control() == "on":
        ctx.log_ok("bluetooth_pm: dongle runtime PM disabled")
    else:
        ctx.log_warn("bluetooth_pm: control still not on — replug the dongle")


STEP = Step(
    name="bluetooth_pm",
    title="keep the RTL8761BU Bluetooth dongle awake via udev",
    requires=("rtl8761bu_bt",),
    run=_run,
)
