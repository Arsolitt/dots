"""Symlink reconciliation and broken-link cleanup."""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Iterator

from .cli import Context

DEFAULT_SCAN_DIRS = (
    Path.home() / ".config",
    Path.home() / ".gnupg",
    Path.home() / ".local/bin",
    Path.home() / "projects",
)


@dataclass
class Link:
    src: str | Path
    dst: str | Path
    optional: bool = False


def _absolute(path: str | Path) -> Path:
    expanded = Path(path).expanduser()
    return expanded if expanded.is_absolute() else expanded.resolve()


class Linker:
    def __init__(
        self,
        ctx: Context,
        root: str | Path,
        backup: bool = True,
        home: str | Path | None = None,
    ) -> None:
        self.ctx = ctx
        self.root = Path(root).expanduser().resolve()
        self.backup = backup
        self.home = Path(home).expanduser() if home else Path.home()

    # -- install ---------------------------------------------------------

    def reconcile(self, links: Iterable[Link]) -> int:
        linked = 0
        for item in links:
            if self._reconcile_one(item):
                linked += 1
        return linked

    def _reconcile_one(self, item: Link) -> bool:
        ctx = self.ctx
        src = _absolute(item.src)
        dst = _absolute(item.dst)

        if not src.exists():
            if not item.optional:
                ctx.log_warn(f"source missing, skip: {src}")
            return False

        canonical_src = Path(os.path.realpath(src))
        canonical_dst = Path(os.path.realpath(dst.parent)) / dst.name
        if canonical_src == canonical_dst:
            ctx.log_warn(f"source equals destination, skip: {dst}")
            return False

        if dst.is_symlink() and os.readlink(dst) == str(src):
            ctx.log_skip(f"already linked: {dst}")
            return False

        if dst.exists() or dst.is_symlink():
            if self.backup:
                backup_path = self._backup_name(dst)
                if ctx.dry_run:
                    ctx.log_info(f"would backup {dst} -> {backup_path}")
                else:
                    dst.rename(backup_path)
                    ctx.log_warn(f"backed up {dst} -> {backup_path}")
            elif ctx.dry_run:
                ctx.log_info(f"would remove existing {dst}")
            else:
                self._remove(dst)
                ctx.log_warn(f"removed existing {dst}")

        ctx.ensure_dir(dst.parent)
        if ctx.dry_run:
            ctx.log_info(f"would link {src} -> {dst}")
            return True
        os.symlink(src, dst)
        ctx.log_ok(f"linked {dst}")
        return True

    def _backup_name(self, dst: Path) -> Path:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        candidate = dst.with_name(f"{dst.name}.backup-{stamp}")
        counter = 1
        while candidate.exists() or candidate.is_symlink():
            candidate = dst.with_name(f"{dst.name}.backup-{stamp}-{counter}")
            counter += 1
        return candidate

    @staticmethod
    def _remove(path: Path) -> None:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()

    # -- cleanup ---------------------------------------------------------

    def cleanup(self, scan_dirs: Iterable[str | Path]) -> int:
        ctx = self.ctx
        ctx.log_info("scanning for broken dotfiles symlinks")
        removed = 0
        for directory in scan_dirs:
            path = Path(directory).expanduser()
            if not path.is_dir():
                continue
            for candidate in self._walk_symlinks(path):
                removed += self._try_remove(candidate)
        for candidate in self._shallow_symlinks(self.home):
            removed += self._try_remove(candidate)
        if removed:
            ctx.log_ok(f"cleaned up {removed} broken link(s)")
        else:
            ctx.log_skip("no broken dotfiles symlinks found")
        return removed

    @staticmethod
    def _walk_symlinks(directory: Path) -> Iterator[Path]:
        for current, dirnames, filenames in os.walk(directory, followlinks=False):
            base = Path(current)
            for name in [*dirnames, *filenames]:
                candidate = base / name
                if candidate.is_symlink():
                    yield candidate

    @staticmethod
    def _shallow_symlinks(directory: Path) -> Iterator[Path]:
        try:
            entries = list(os.scandir(directory))
        except OSError:
            return
        for entry in entries:
            candidate = Path(entry.path)
            if candidate.is_symlink():
                yield candidate

    def _try_remove(self, linkpath: Path) -> int:
        try:
            target = os.readlink(linkpath)
        except OSError:
            return 0
        if target != str(self.root) and not target.startswith(f"{self.root}{os.sep}"):
            return 0
        if os.path.exists(linkpath):
            return 0
        if self.ctx.dry_run:
            self.ctx.log_info(f"would remove broken link: {linkpath}")
            return 1
        try:
            linkpath.unlink()
        except OSError as exc:
            self.ctx.log_err(f"cannot remove broken link {linkpath}: {exc}")
            return 0
        self.ctx.log_warn(f"removed broken link: {linkpath}")
        return 1
