"""tmux plugin manager, cloned from GitHub when missing."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step

TPM_URL = "https://github.com/tmux-plugins/tpm"


def _run(ctx: Context) -> None:
    target = Path.home() / ".tmux" / "plugins" / "tpm"
    if target.is_dir():
        ctx.log_skip("tpm: already installed")
        return
    ctx.ensure_dir(target.parent)
    before = len(ctx.errors)
    ctx.run(["git", "clone", "--quiet", TPM_URL, str(target)])
    if not ctx.dry_run and len(ctx.errors) == before:
        ctx.log_ok("tpm: cloned into ~/.tmux/plugins/tpm")


STEP = Step(name="tpm", title="install tmux plugin manager", run=_run)
