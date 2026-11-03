"""Symlink repository configs into $HOME, honouring the device profile."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

from ..cli import Context
from ..links import DEFAULT_SCAN_DIRS, Link, Linker
from ..profile import Profile
from . import Step

CONFIG_DIRS = ("fish", "git", "kitty", "btop", "tmux", "nvim")
LINUX_DIRS = ("hypr", "swappy", "swayimg", "nwg-look", "gtk-2.0", "gtk-3.0", "gtk-4.0", "noctalia")
LINUX_FILES = ("mimeapps.list", "electron-flags.conf")
BIN_FILES = (
    "bin/opus-bench",
    "bin/ssh-askpass-fprint",
    "bin/ssh-askpass-gui",
    "bin/ssh-askpass-keyring",
    "bin/ssh-unlock.fish",
    "gpg-export.fish",
    "gpg-import.fish",
    "yay.fish",
)
PIPEWIRE_SOURCE = "pipewire/mic-denoise-rnnoise.conf"
PIPEWIRE_DEST = ".config/pipewire/pipewire.conf.d/50-mic-denoise.conf"
NPU_SERVICE = "systemd/user/npu-denoise.service"
NPU_HOST = "npu-denoise"

LADSPA_DIR = Path("/usr/lib/ladspa")
LADSPA_DEST = ".local/lib/ladspa"
LADSPA_PLUGINS = (
    ("libdeep_filter_ladspa.so", "deepfilternet-ladspa"),
    ("librnnoise_ladspa.so", "noise-suppression-for-voice"),
)

REQUIRED_DIRS = (
    ".config",
    ".gnupg",
    ".local/bin",
    ".config/pbackup",
    ".config/pipewire/pipewire.conf.d",
    ".config/systemd/user",
    "projects",
)


def _built_in(ctx: Context) -> list[Link]:
    home = Path.home()
    links: list[Link] = []

    for name in CONFIG_DIRS:
        links.append(Link(ctx.root / name, home / ".config" / name))

    links.append(Link(ctx.root / "starship.toml", home / ".config/starship.toml"))
    links.append(Link(ctx.root / "pbackup/config.toml",
                      home / ".config/pbackup/config.toml"))
    links.append(Link(ctx.root / "gpg-agent.conf", home / ".gnupg/gpg-agent.conf"))

    for name in LINUX_DIRS:
        links.append(Link(ctx.root / name, home / ".config" / name))
    for name in LINUX_FILES:
        links.append(Link(ctx.root / name, home / ".config" / name))

    for name in BIN_FILES:
        links.append(Link(ctx.root / name, home / ".local/bin" / Path(name).name))

    links.append(Link(ctx.root / PIPEWIRE_SOURCE, home / PIPEWIRE_DEST))
    links.extend(_ladspa_links(ctx, home))

    if ctx.feature("npu"):
        links.append(
            Link(ctx.root / NPU_SERVICE,
                 home / ".config/systemd/user" / Path(NPU_SERVICE).name)
        )
        links.append(Link(ctx.root / NPU_HOST, home / "projects" / NPU_HOST))

    return links


def _ladspa_links(ctx: Context, home: Path) -> list[Link]:
    links: list[Link] = []
    for plugin, package in LADSPA_PLUGINS:
        source = LADSPA_DIR / plugin
        if not source.exists():
            ctx.log_warn(f"ladspa plugin missing, install {package}: {source}")
            continue
        links.append(Link(source, home / LADSPA_DEST / plugin, optional=True))
    return links


def _skips(link: Link, root: Path, patterns: Sequence[str]) -> bool:
    source = Path(link.src)
    destination = Path(link.dst)
    identities = {source.name, str(source), str(destination)}
    try:
        identities.add(str(source.relative_to(root)))
    except ValueError:
        pass
    for raw in patterns:
        pattern = str(raw)
        if pattern in identities:
            return True
        if Path(pattern).expanduser() in (source, destination):
            return True
    return False


def _extra_links(profile: Profile, root: Path) -> list[Link]:
    links: list[Link] = []
    for source, destination in profile.extra_links:
        path = Path(source).expanduser()
        if not path.is_absolute():
            path = Path(root) / path
        links.append(Link(path, Path(destination).expanduser()))
    return links


def _run(ctx: Context) -> None:
    home = Path.home()
    linker = Linker(ctx, ctx.root, backup=not ctx.no_backup)
    linker.cleanup(DEFAULT_SCAN_DIRS)

    for relative in REQUIRED_DIRS:
        ctx.ensure_dir(home / relative)

    profile = ctx.profile or Profile()
    links = [
        link
        for link in _built_in(ctx)
        if not _skips(link, ctx.root, profile.skip_links)
    ]
    links.extend(_extra_links(profile, ctx.root))

    installed = linker.reconcile(links)
    if installed:
        ctx.log_ok(f"configs: {installed} link(s) installed")
    else:
        ctx.log_skip("configs: all links already in place")


STEP = Step(name="configs", title="symlink dotfiles into $HOME", run=_run)
