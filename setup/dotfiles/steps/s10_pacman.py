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
    "ripgrep",
    "fish",
    "btop",
    "neovim",
    "git",
    "jq",
    "cloc",
    "fnm",
    "kubectl",
    "go",
    "gnupg",
    "age",
    "sops",
    "ansible",
    "openssh",
    "restic",
    "pass",
    "rsync",
    "curl",
    "rust",
    "cilium-cli",
    "tmux",
    "libsecret",
    "uv",
    "docker",
    "docker-compose",
    "docker-buildx",
    "base-devel",
    "github-cli",
    "opentofu",
    "bind",
    "pacman-contrib",
    "dmidecode",
    "smartmontools",
    "usbutils",
)

DESKTOP_PACKAGES = (
    "hyprland",
    "greetd",
    "uwsm",
    "hyprpicker",
    "noctalia",
    "noctalia-greeter",
    "zen-browser-bin",
    "sof-firmware",
    "alsa-firmware",
    "alsa-utils",
    "alsa-plugins",
    "pipewire",
    "pipewire-pulse",
    "pipewire-alsa",
    "wireplumber",
    "bluez",
    "bluez-utils",
    "pavucontrol",
    "networkmanager",
    "networkmanager-openvpn",
    "wpa_supplicant",
    "kitty",
    "mate-polkit",
    "gnome-keyring",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
    "xdg-desktop-portal-gtk",
    "xdg-user-dirs",
    "grim",
    "slurp",
    "wl-clipboard",
    "swappy",
    "swayimg",
    "satty",
    "swash",
    "wf-recorder",
    "nwg-look",
    "nemo",
    "engrampa",
    "unrar",
    "nemo-python",
    "nemo-image-converter",
    "nemo-terminal",
    "nemo-compare",
    "nemo-emblems",
    "nemo-audio-tab",
    "ffmpegthumbnailer",
    "poppler-glib",
    "7zip",
    "qt6ct",
    "telegram-desktop",
    "code",
    "obsidian",
    "gnome-calculator",
    "brightnessctl",
    "noto-fonts",
    "noto-fonts-emoji",
    "noto-fonts-cjk",
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
