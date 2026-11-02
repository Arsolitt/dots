"""Keep power-profiles-daemon off the broken ACPI platform_profile path."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step

DROPIN = Path("/etc/systemd/system/power-profiles-daemon.service.d/10-cpu-only.conf")
SCRIPT = "power-profile/ppd-platform-driver.sh"
FLAG = "--block-driver=platform_profile"


def _installed(ctx: Context) -> bool:
    return (
        DROPIN.is_file()
        and not ctx.dry_run
        and ctx.ok(["grep", "-q", "--", FLAG, str(DROPIN)])
    )


def _run(ctx: Context) -> None:
    script = ctx.root / SCRIPT
    if not script.is_file():
        ctx.log_err(f"power profile: missing install script {script}")
        return
    if _installed(ctx):
        ctx.log_skip("power profile: platform_profile driver already blocked")
        return
    ctx.run([script, "install"], sudo=True)


STEP = Step(
    name="power_profile",
    title="keep ppd off the ACPI platform_profile path",
    requires=("platform_profile_fix",),
    run=_run,
)
