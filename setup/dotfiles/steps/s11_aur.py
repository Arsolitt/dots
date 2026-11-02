"""AUR packages installed through yay."""

from __future__ import annotations

from .. import packages
from ..cli import Context
from . import Step

AUR_PACKAGES = (
    "fluxcd",
    "vesktop",
    "netbird-bin",
    "netbird-ui-bin",
    "kanagawa-gtk-theme-git",
    "kanagawa-icon-theme-git",
    "vimix-kanagawa-cursors",
    "gtk-engine-murrine",
    "ttf-pacifico",
    "ttf-montserrat",
    "maplemono-nf-cn-unhinted",
)


def _run(ctx: Context) -> None:
    missing = [pkg for pkg in AUR_PACKAGES if not packages.installed(pkg)]
    if not missing:
        ctx.log_skip(f"aur: all {len(AUR_PACKAGES)} package(s) already installed")
        return
    if not ctx.have("yay"):
        for pkg in missing:
            ctx.log_warn(f"yay not found; install {pkg} with: yay -S {pkg}")
        return
    ctx.log_info(f"aur: installing {len(missing)} package(s)")
    packages.aur_install(ctx, missing)


STEP = Step(name="aur", title="install AUR packages", run=_run)
