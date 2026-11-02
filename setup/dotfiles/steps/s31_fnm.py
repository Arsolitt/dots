"""Install the Node LTS release through fnm when none is present."""

from __future__ import annotations

from ..cli import Context
from . import Step


def _run(ctx: Context) -> None:
    if not ctx.have("fnm"):
        ctx.log_err("fnm: not found — the pacman step should have installed it")
        return

    listing = ctx.capture(["fnm", "list"]) or ""
    if listing.strip():
        ctx.log_skip("fnm: node already installed")
        return

    before = len(ctx.errors)
    ctx.run(["fnm", "install", "--lts"])
    if len(ctx.errors) != before:
        return
    ctx.run(["fnm", "default", "lts-latest"])
    if not ctx.dry_run and len(ctx.errors) == before:
        ctx.log_ok("fnm: installed node LTS")


STEP = Step(name="fnm", title="install Node LTS via fnm", run=_run)
