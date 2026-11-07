"""Logging helpers and the shared execution context."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Sequence

if TYPE_CHECKING:
    from .profile import Profile

_ANSI = {
    "blue": "\033[34m",
    "green": "\033[32m",
    "bright_black": "\033[90m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "reset": "\033[0m",
}


def _paint(text: str, color: str, stream) -> str:
    if not stream.isatty():
        return text
    return f"{_ANSI[color]}{text}{_ANSI['reset']}"


def _glyph(char: str, color: str, stream) -> str:
    return _paint(f"{char:>2}", color, stream)


@dataclass
class Context:
    """Execution context shared by every step.

    ``features`` holds the resolved feature flags and ``errors`` every
    recorded failure; a non-empty list means the process exits non-zero.
    """

    root: Path
    dry_run: bool = False
    assume_yes: bool = False
    no_backup: bool = False
    features: dict[str, bool] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    profile: Profile | None = None

    def feature(self, name: str) -> bool:
        return bool(self.features.get(name, False))

    def log_info(self, message: str) -> None:
        print(f"{_paint('==>', 'blue', sys.stdout)} {message}")

    def log_ok(self, message: str) -> None:
        print(f"{_glyph(' +', 'green', sys.stdout)}  {message}")

    def log_skip(self, message: str) -> None:
        print(f"{_glyph(' .', 'bright_black', sys.stdout)}  {_paint(message, 'bright_black', sys.stdout)}")

    def log_warn(self, message: str) -> None:
        print(f"{_glyph(' !', 'yellow', sys.stdout)}  {message}")

    def log_err(self, message: str) -> None:
        self.errors.append(message)
        print(f"{_glyph(' x', 'red', sys.stderr)}  {message}", file=sys.stderr)

    def run(
        self,
        cmd: Sequence[str | Path],
        sudo: bool = False,
        cwd: str | Path | None = None,
        check: bool = True,
        capture: bool = False,
        env: dict[str, str] | None = None,
    ) -> str | None:
        argv = [str(part) for part in cmd]
        if sudo and os.geteuid() != 0:
            argv = ["sudo", *argv]

        if self.dry_run:
            self.log_info(f"would run: {' '.join(argv)}")
            return None

        result = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0 and check:
            self.log_err(f"command failed ({result.returncode}): {' '.join(argv)}")
            stderr = result.stderr.strip()
            if stderr:
                self.log_err(stderr)
        return result.stdout if capture else None

    def capture(self, cmd: Sequence[str | Path], sudo: bool = False,
                cwd: str | Path | None = None) -> str | None:
        """Quiet probe: returns stdout and never records an error."""
        return self.run(cmd, sudo=sudo, cwd=cwd, check=False, capture=True)

    def have(self, command: str) -> bool:
        return shutil.which(command) is not None

    def ok(self, cmd: Sequence[str | Path], sudo: bool = False,
           cwd: str | Path | None = None) -> bool:
        """Quiet boolean probe for guards; dry-run reports a planned run."""
        argv = [str(part) for part in cmd]
        if sudo and os.geteuid() != 0:
            argv = ["sudo", *argv]
        if self.dry_run:
            self.log_info(f"would run: {' '.join(argv)}")
            return True
        return subprocess.run(argv, cwd=cwd, capture_output=True).returncode == 0

    def read(self, cmd: Sequence[str | Path], cwd: str | Path | None = None) -> str:
        """Read-only probe executed even in dry-run; returns stdout or ''."""
        result = subprocess.run(
            [str(part) for part in cmd],
            cwd=cwd,
            text=True,
            capture_output=True,
        )
        return result.stdout if result.returncode == 0 else ""

    def ensure_dir(self, path: str | Path) -> None:
        directory = Path(path).expanduser()
        if directory.is_dir():
            return
        if self.dry_run:
            self.log_info(f"would create dir {directory}")
            return
        directory.mkdir(parents=True, exist_ok=True)
        self.log_ok(f"created dir {directory}")
