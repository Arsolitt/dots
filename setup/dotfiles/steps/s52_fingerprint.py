"""Fingerprint authentication: fprintd packages and PAM entries."""

from __future__ import annotations

import tempfile
from datetime import datetime
from pathlib import Path

from .. import packages
from ..cli import Context
from . import Step

PACKAGES = ("fprintd", "libfprint")
PAM_FILES = (
    Path("/etc/pam.d/sudo"),
    Path("/etc/pam.d/polkit-1"),
    Path("/etc/pam.d/greetd"),
)
PAM_LINE = "auth sufficient pam_fprintd.so # dots"


def _backup_name(target: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return target.with_name(f"{target.name}.dots-backup-{stamp}")


def _install_pam(ctx: Context, target: Path) -> None:
    try:
        content = target.read_text(encoding="utf-8")
    except OSError as exc:
        ctx.log_warn(f"fingerprint: cannot read {target}: {exc}")
        return

    if "pam_fprintd.so" in content:
        ctx.log_skip(f"fingerprint: {target} already has a pam_fprintd entry")
        return

    backup = _backup_name(target)
    if ctx.dry_run:
        ctx.log_info(f"would backup {target} -> {backup}")
        ctx.log_info(f"would prepend to {target}: {PAM_LINE}")
        return

    ctx.run(["cp", "-p", str(target), str(backup)], sudo=True)

    handle = tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        prefix="dots-pam-",
        suffix=".conf",
        delete=False,
    )
    temp = Path(handle.name)
    try:
        with handle:
            handle.write(f"{PAM_LINE}\n{content}")
        ctx.run(["install", "-m", "0644", str(temp), str(target)], sudo=True)
    finally:
        temp.unlink(missing_ok=True)


def _run(ctx: Context) -> None:
    ctx.log_info("fingerprint: installing fprintd and wiring PAM")
    packages.install(ctx, PACKAGES)
    for target in PAM_FILES:
        if target.is_file():
            _install_pam(ctx, target)
    ctx.log_info("fingerprint: enroll a finger with: fprintd-enroll")


STEP = Step(
    name="fingerprint",
    title="install fprintd and enable PAM fingerprint auth",
    requires=("fingerprint",),
    run=_run,
)
