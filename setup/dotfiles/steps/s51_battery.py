"""Install the firmware 80% battery charge limit."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step

BINARY = Path("/usr/local/sbin/charge-limit")
UNIT = "battery-charge-limit.service"
SCRIPT = "battery/charge-limit.sh"


def _run(ctx: Context) -> None:
    if (
        BINARY.exists()
        and not ctx.dry_run
        and ctx.ok(["systemctl", "is-enabled", "--quiet", UNIT])
    ):
        ctx.log_skip(f"battery: charge limit already installed and {UNIT} enabled")
        return

    script = ctx.root / SCRIPT
    if not script.is_file():
        ctx.log_err(f"battery: missing install script {script}")
        return
    ctx.run([script, "install"], sudo=True)


STEP = Step(
    name="battery",
    title="install the 80% battery charge limit",
    requires=("charge_limit",),
    run=_run,
)
