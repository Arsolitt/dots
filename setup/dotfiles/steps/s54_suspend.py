"""Rebind bitland-mifs-wmi around suspend; its 7.3.1 callback aborts sleep."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step

HOOK = Path("/etc/systemd/system-sleep/bitland-mifs-wmi.sh")
SCRIPT = "suspend/bitland-sleep.sh"


def _installed(ctx: Context) -> bool:
    return (
        HOOK.is_file()
        and not ctx.dry_run
        and ctx.ok([ctx.root / SCRIPT, "check"])
    )


def _run(ctx: Context) -> None:
    script = ctx.root / SCRIPT
    if not script.is_file():
        ctx.log_err(f"suspend: missing install script {script}")
        return
    if _installed(ctx):
        ctx.log_skip("suspend: bitland-mifs-wmi hook already installed")
        return
    ctx.run([script, "install"], sudo=True)


STEP = Step(
    name="suspend_fix",
    title="rebind bitland-mifs-wmi around suspend",
    requires=("bitland_sleep_fix",),
    run=_run,
)
