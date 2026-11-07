"""Deploy the greetd greeter config and enable the login-session services."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from ..cli import Context
from . import Step

CONFIG = Path("/etc/greetd/config.toml")
ARTIFACT = "greetd/config.toml"
UNITS = ("greetd", "bluetooth", "NetworkManager")
UNIT_DIRS = (
    Path("/etc/systemd/system"),
    Path("/run/systemd/system"),
    Path("/usr/lib/systemd/system"),
)


def _backup_name(target: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return target.with_name(f"{target.name}.dots-backup-{stamp}")


def _unit_file(unit: str) -> bool:
    return any((directory / f"{unit}.service").is_file() for directory in UNIT_DIRS)


def _deploy_config(ctx: Context) -> None:
    artifact = ctx.root / ARTIFACT
    if not artifact.is_file():
        ctx.log_err(f"session: missing {artifact}")
        return

    desired = artifact.read_text(encoding="utf-8")
    try:
        current = CONFIG.read_text(encoding="utf-8")
    except OSError:
        current = None

    if current == desired:
        ctx.log_skip(f"session: {CONFIG} already matches the repo artifact")
        return

    backup = _backup_name(CONFIG)
    if ctx.dry_run:
        if current is not None:
            ctx.log_info(f"would backup {CONFIG} -> {backup}")
        ctx.log_info(f"would install {artifact} -> {CONFIG}")
        return

    if current is not None:
        ctx.run(["cp", "-p", str(CONFIG), str(backup)], sudo=True)
    ctx.run(["install", "-m", "0644", str(artifact), str(CONFIG)], sudo=True)


def _enable_units(ctx: Context) -> None:
    if not ctx.have("systemctl"):
        ctx.log_warn("session: systemctl not available — enable units manually")
        return

    for unit in UNITS:
        if not _unit_file(unit):
            ctx.log_skip(f"session: no unit file for {unit}")
            continue
        if ctx.ok(["systemctl", "is-enabled", "--quiet", unit]):
            ctx.log_skip(f"session: {unit} already enabled")
            continue
        ctx.run(["systemctl", "enable", unit], sudo=True)


def _run(ctx: Context) -> None:
    _deploy_config(ctx)
    _enable_units(ctx)


STEP = Step(
    name="session",
    title="deploy greetd session and enable services",
    run=_run,
)
