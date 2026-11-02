"""Pacman packages: base, desktop and feature-gated sets."""

from __future__ import annotations

from .. import packages
from ..cli import Context
from . import Step

BASE_PACKAGES = (
    "starship",
    "zoxide",
    "eza",
    "bat",
    "fd",
    "fzf",
    "git",
    "jq",
    "cloc",
    "fnm",
    "kubectl",
    "go",
    "gnupg",
    "restic",
    "pass",
    "rsync",
    "rust",
    "cilium-cli",
    "tmux",
    "libsecret",
    "uv",
    "docker",
    "docker-compose",
    "docker-buildx",
)

DESKTOP_PACKAGES = (
    "hyprland",
    "hyprlock",
    "hypridle",
    "hyprpicker",
    "noctalia",
    "kitty",
    "mate-polkit",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
    "xdg-desktop-portal-gtk",
    "grim",
    "slurp",
    "wl-clipboard",
    "swappy",
    "swayimg",
    "satty",
    "wf-recorder",
    "nwg-look",
    "telegram-desktop",
    "ttf-fantasque-nerd",
    "deepfilternet-ladspa",
    "noise-suppression-for-voice",
)

NPU_PACKAGES = ("level-zero-loader", "intel-npu-driver", "intel-npu-compiler")
CHARGE_LIMIT_PACKAGES = ("acpi_call-dkms",)
FINGERPRINT_PACKAGES = ("fprintd", "libfprint")


def _wanted(ctx: Context) -> list[str]:
    wanted = [*BASE_PACKAGES, *DESKTOP_PACKAGES]
    if ctx.feature("npu"):
        wanted.extend(NPU_PACKAGES)
    if ctx.feature("charge_limit"):
        wanted.extend(CHARGE_LIMIT_PACKAGES)
    if ctx.feature("fingerprint"):
        wanted.extend(FINGERPRINT_PACKAGES)

    loaded = getattr(ctx, "profile", None)
    if loaded is not None:
        wanted.extend(str(pkg) for pkg in getattr(loaded, "extra_packages", ()))
    return wanted


def _run(ctx: Context) -> None:
    wanted = _wanted(ctx)
    missing = [pkg for pkg in wanted if not packages.installed(pkg)]
    if not missing:
        ctx.log_skip(f"pacman: all {len(wanted)} package(s) already installed")
        return
    ctx.log_info(
        f"pacman: installing {len(missing)} of {len(wanted)} package(s): "
        f"{' '.join(missing)}"
    )
    packages.install(ctx, missing)


STEP = Step(name="pacman", title="install pacman packages", run=_run)
