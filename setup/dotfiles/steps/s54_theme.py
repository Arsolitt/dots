"""Seed kitty's noctalia theme file ahead of noctalia's first wallpaper render."""

from __future__ import annotations

import shutil
from pathlib import Path

from ..cli import Context
from . import Step


def _run(ctx: Context) -> None:
    source = ctx.root / "kitty" / "current-theme.conf"
    target_dir = ctx.root / "kitty" / "themes"
    target = target_dir / "noctalia.conf"
    if not source.is_file():
        ctx.log_skip("theme: no kitty/current-theme.conf to bootstrap from")
        return
    if target.is_file():
        ctx.log_skip("theme: kitty noctalia theme already present")
        return
    ctx.ensure_dir(target_dir)
    if ctx.dry_run:
        ctx.log_info(f"would copy {source.name} to {target}")
        return
    shutil.copyfile(source, target)
    ctx.log_ok("theme: bootstrapped kitty/themes/noctalia.conf from current-theme.conf")


STEP = Step(
    name="theme",
    title="Wallpaper theme bootstrap",
    run=_run,
)
