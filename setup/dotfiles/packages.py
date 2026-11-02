"""Package helpers: pacman for official repos, yay for the AUR."""

from __future__ import annotations

import subprocess
from typing import Iterable

from .cli import Context


def _unique(pkgs: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for pkg in pkgs:
        if pkg not in seen:
            seen.add(pkg)
            ordered.append(pkg)
    return ordered


def installed(pkg: str) -> bool:
    """Quiet probe: is the package installed according to pacman?"""
    try:
        result = subprocess.run(
            ["pacman", "-Q", pkg],
            text=True,
            capture_output=True,
        )
    except FileNotFoundError:
        return False
    return result.returncode == 0


def install(ctx: Context, pkgs: Iterable[str]) -> None:
    """Install the missing subset of ``pkgs`` with one pacman call."""
    missing = [pkg for pkg in _unique(pkgs) if not installed(pkg)]
    if not missing:
        return
    ctx.run(
        ["pacman", "-S", "--needed", "--noconfirm", "--", *missing],
        sudo=True,
    )


def aur_install(ctx: Context, pkgs: Iterable[str]) -> None:
    """Install AUR packages one by one, skipping everything when yay is absent."""
    wanted = _unique(pkgs)
    if not wanted:
        return
    if not ctx.have("yay"):
        ctx.log_warn(
            "yay not found; install the AUR packages with: "
            f"yay -S --needed --noconfirm {' '.join(wanted)}"
        )
        return
    for pkg in wanted:
        if installed(pkg):
            ctx.log_skip(f"already installed: {pkg}")
            continue
        ctx.run(["yay", "-S", "--needed", "--noconfirm", pkg])
