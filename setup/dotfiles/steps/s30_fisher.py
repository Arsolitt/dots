"""fisher plugin manager: install when missing, then reconcile plugins."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step

INSTALL_COMMAND = (
    "curl -fsSL "
    "https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish "
    "| source; and fisher install jorgebucaran/fisher"
)


def _installed(ctx: Context) -> bool:
    if (Path.home() / ".config" / "fish" / "functions" / "fisher.fish").is_file():
        return True
    # A missing fish binary is a prerequisite failure logged by the install run.
    return not ctx.dry_run and ctx.ok(["fish", "-c", "functions --query fisher"])


def _run(ctx: Context) -> None:
    if _installed(ctx):
        ctx.log_skip("fisher: already installed")
    else:
        ctx.run(["fish", "-c", INSTALL_COMMAND])

    if ctx.dry_run:
        ctx.log_info("would run: fish -c 'fisher update'")
        return
    if ctx.ok(["fish", "-c", "fisher update"]):
        ctx.log_ok("fisher: plugins reconciled")
    else:
        ctx.log_warn("fisher: update reported issues (may be harmless)")


STEP = Step(name="fisher", title="install fisher and reconcile plugins", run=_run)
