"""Make fish the login shell, registering it in /etc/shells first."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

from ..cli import Context
from . import Step

SHELLS_FILE = Path("/etc/shells")


def _resolved(path: str) -> str:
    try:
        return str(Path(path).resolve())
    except OSError:
        return path


def _has_entry(lines: list[str], fish: str) -> bool:
    entries = {
        line.strip()
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    }
    if fish in entries:
        return True
    resolved = {_resolved(entry) for entry in entries}
    return _resolved(fish) in resolved


def _add_to_shells(ctx: Context, fish: str) -> None:
    try:
        lines = SHELLS_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    if _has_entry(lines, fish):
        ctx.log_skip(f"shell: {fish} already listed in {SHELLS_FILE}")
        return
    if ctx.dry_run:
        ctx.log_info(f"would add {fish} to {SHELLS_FILE}")
        return

    with tempfile.TemporaryDirectory(prefix="dots-shells-") as raw:
        staged = Path(raw) / "shells"
        staged.write_text("\n".join([*lines, fish]) + "\n", encoding="utf-8")
        before = len(ctx.errors)
        # install(1) replaces the file atomically without a shell pipeline.
        ctx.run(["install", "-m", "0644", str(staged), str(SHELLS_FILE)], sudo=True)
        if len(ctx.errors) == before:
            ctx.log_ok(f"shell: added {fish} to {SHELLS_FILE}")


def _run(ctx: Context) -> None:
    fish = shutil.which("fish")
    if fish is None:
        ctx.log_err("shell: fish not found on PATH")
        return

    current = os.environ.get("SHELL", "")
    if current and _resolved(current) == _resolved(fish):
        ctx.log_skip(f"shell: already {fish}")
        return

    _add_to_shells(ctx, fish)
    before = len(ctx.errors)
    ctx.run(["chsh", "-s", fish])
    if not ctx.dry_run and len(ctx.errors) == before:
        ctx.log_ok(f"shell: default shell set to {fish} — relogin to apply")


STEP = Step(name="shell", title="set fish as the login shell", run=_run)
