"""Nemo defaults: kitty as the external terminal, embedded pane hidden (F4 still toggles), desktop handling off."""

from __future__ import annotations

from ..cli import Context
from . import Step

SETTINGS = (
    # nemo spawns this with cwd = clicked folder; the stock gnome-terminal default is absent here
    ("org.cinnamon.desktop.default-applications.terminal", "exec", "kitty"),
    ("org.nemo.extensions.nemo-terminal", "default-visible", "false"),
    # desktop-manager init adds ~0.35s to every launch; desktop icons are unused on Hyprland (no nemo-desktop autostart)
    ("org.nemo.desktop", "show-desktop-icons", "false"),
)


def _run(ctx: Context) -> None:
    if not ctx.have("gsettings"):
        ctx.log_skip("nemo: gsettings not available")
        return
    schemas = ctx.read(["gsettings", "list-schemas"])
    for schema, key, value in SETTINGS:
        if schema not in schemas:
            ctx.log_skip(f"nemo: schema {schema} not installed, skipping {key}")
            continue
        current = ctx.read(["gsettings", "get", schema, key]).strip().strip("'")
        if current == value:
            ctx.log_skip(f"nemo: {key} already {value}")
            continue
        ctx.run(["gsettings", "set", schema, key, value])
        if not ctx.dry_run:
            ctx.log_ok(f"nemo: {schema} {key} -> {value}")


STEP = Step(
    name="nemo",
    title="Nemo defaults",
    run=_run,
)

