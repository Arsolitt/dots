"""Install krew, the kubectl plugin manager, from its release archive."""

from __future__ import annotations

import os
import platform
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from ..cli import Context
from . import Step

RELEASE_URL = (
    "https://github.com/kubernetes-sigs/krew/releases/latest/download/{asset}.tar.gz"
)
USER_AGENT = "dots-installer (+https://github.com/arsolitt/dots)"


def _arch() -> str:
    machine = platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        return "amd64"
    if machine in {"aarch64", "arm64"}:
        return "arm64"
    raise RuntimeError(f"krew: unsupported architecture {machine!r}")


def _download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, destination.open(
        "wb"
    ) as handle:
        shutil.copyfileobj(response, handle)


def _safe_extract(archive: tarfile.TarFile, destination: Path) -> None:
    """Extract regular files and directories, rejecting traversal and links."""
    root = destination.resolve()
    for member in archive.getmembers():
        target = (root / member.name).resolve()
        if target != root and root not in target.parents:
            raise RuntimeError(f"krew: refusing unsafe archive member {member.name!r}")
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        if not member.isfile():
            raise RuntimeError(
                f"krew: refusing non-regular archive member {member.name!r}"
            )
        source = archive.extractfile(member)
        if source is None:
            raise RuntimeError(f"krew: cannot read archive member {member.name!r}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read())
        target.chmod(member.mode & 0o777 or 0o644)


def _run(ctx: Context) -> None:
    krew_binary = Path.home() / ".krew" / "bin" / "kubectl-krew"
    if krew_binary.is_file() and os.access(krew_binary, os.X_OK):
        ctx.log_skip("krew: already installed")
        return
    if ctx.dry_run:
        ctx.log_info("would install krew from the latest GitHub release")
        return

    asset = f"krew-linux_{_arch()}"
    url = RELEASE_URL.format(asset=asset)
    ctx.log_info(f"krew: installing from {url}")

    with tempfile.TemporaryDirectory(prefix="dots-krew-") as raw:
        work = Path(raw)
        archive_path = work / f"{asset}.tar.gz"
        _download(url, archive_path)
        with tarfile.open(archive_path, "r:gz") as archive:
            _safe_extract(archive, work)
        installer = work / asset
        if not installer.is_file():
            raise RuntimeError("krew: release archive did not contain the installer")
        installer.chmod(0o755)
        before = len(ctx.errors)
        ctx.run([str(installer), "install", "krew"], cwd=work)
        if len(ctx.errors) == before:
            ctx.log_ok("krew: installed")


STEP = Step(name="krew", title="install krew", run=_run)
