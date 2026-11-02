"""Build the pbackup CLI into ~/.local/bin when sources are newer."""

from __future__ import annotations

from pathlib import Path

from ..cli import Context
from . import Step


def _newest_source(source_dir: Path) -> float:
    candidates = list(source_dir.rglob("*.go"))
    candidates.append(source_dir / "go.mod")
    stamps = [path.stat().st_mtime for path in candidates if path.is_file()]
    return max(stamps, default=0.0)


def _run(ctx: Context) -> None:
    if not ctx.have("go"):
        ctx.log_err("pbackup: go not found — cannot build the CLI")
        return

    source_dir = ctx.root / "pbackup"
    if not source_dir.is_dir():
        ctx.log_err(f"pbackup: source directory missing at {source_dir}")
        return

    target_dir = Path.home() / ".local" / "bin"
    binary = target_dir / "pbackup"
    ctx.ensure_dir(target_dir)

    if binary.is_file() and binary.stat().st_mtime >= _newest_source(source_dir):
        ctx.log_skip("pbackup: binary is up to date")
        return

    before = len(ctx.errors)
    ctx.run(
        ["go", "build", "-C", str(source_dir), "-o", str(binary), "."],
    )
    if not ctx.dry_run and len(ctx.errors) == before:
        ctx.log_ok(f"pbackup: built {binary}")


STEP = Step(name="pbackup", title="build the pbackup CLI", run=_run)
