"""Package helpers: pacman for official repos, yay for the AUR."""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import Iterable

from .cli import Context


def _aur_env() -> dict[str, str]:
    """Env for yay: makepkg must build against the system toolchain.

    ``uv run`` puts PEP 723 venv dirs and uv-managed interpreters first in
    PATH, so makepkg resolves ``python`` to them and AUR builds die on
    missing build/setuptools. Drop PATH entries shadowing the system python.
    """
    env = os.environ.copy()
    env.pop("VIRTUAL_ENV", None)
    env.pop("PYTHONPATH", None)
    parts = [part for part in env.get("PATH", "").split(os.pathsep) if part]
    while parts:
        resolved = shutil.which("python", path=os.pathsep.join(parts))
        if resolved is None or os.path.realpath(resolved).startswith("/usr/"):
            break
        drop = os.path.dirname(os.path.abspath(resolved))
        parts = [part for part in parts if os.path.abspath(part) != drop]
    env["PATH"] = os.pathsep.join(parts)
    return env


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
        ctx.run(["yay", "-S", "--needed", "--noconfirm", pkg], env=_aur_env())
