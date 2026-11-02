"""Install kubecm from the latest GitHub release."""

from __future__ import annotations

import json
import platform
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from ..cli import Context
from . import Step

API_URL = "https://api.github.com/repos/sunny0826/kubecm/releases/latest"
DOWNLOAD_URL = "https://github.com/sunny0826/kubecm/releases/download/{tag}/{asset}"
DESTINATION = Path("/usr/local/bin/kubecm")
USER_AGENT = "dots-installer (+https://github.com/arsolitt/dots)"


def _arch() -> str:
    machine = platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        return "x86_64"
    if machine in {"aarch64", "arm64"}:
        return "arm64"
    raise RuntimeError(f"kubecm: unsupported architecture {machine!r}")


def _latest_tag() -> str:
    request = urllib.request.Request(
        API_URL,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        data = json.load(response)
    tag = str(data.get("tag_name") or "").strip()
    if not tag:
        raise RuntimeError("kubecm: latest release response has no tag_name")
    return tag


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
            raise RuntimeError(f"kubecm: refusing unsafe archive member {member.name!r}")
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        if not member.isfile():
            raise RuntimeError(
                f"kubecm: refusing non-regular archive member {member.name!r}"
            )
        source = archive.extractfile(member)
        if source is None:
            raise RuntimeError(f"kubecm: cannot read archive member {member.name!r}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read())
        target.chmod(member.mode & 0o777 or 0o644)


def _binary(directory: Path) -> Path:
    direct = directory / "kubecm"
    if direct.is_file():
        return direct
    matches = [path for path in directory.rglob("kubecm") if path.is_file()]
    if len(matches) != 1:
        raise RuntimeError("kubecm: release archive did not contain a kubecm binary")
    return matches[0]


def _run(ctx: Context) -> None:
    if ctx.have("kubecm"):
        ctx.log_skip("kubecm: already installed")
        return
    if ctx.dry_run:
        ctx.log_info(
            f"would install kubecm from the latest GitHub release to {DESTINATION}"
        )
        return

    tag = _latest_tag()
    asset = f"kubecm_{tag}_Linux_{_arch()}.tar.gz"
    url = DOWNLOAD_URL.format(tag=tag, asset=asset)
    ctx.log_info(f"kubecm: installing {tag} from {url}")

    with tempfile.TemporaryDirectory(prefix="dots-kubecm-") as raw:
        work = Path(raw)
        archive_path = work / asset
        _download(url, archive_path)
        with tarfile.open(archive_path, "r:gz") as archive:
            _safe_extract(archive, work)
        before = len(ctx.errors)
        ctx.run(
            ["install", "-m", "0755", str(_binary(work)), str(DESTINATION)],
            sudo=True,
        )
        if len(ctx.errors) == before:
            ctx.log_ok(f"kubecm: installed {tag} to {DESTINATION}")


STEP = Step(name="kubecm", title="install kubecm", run=_run)
