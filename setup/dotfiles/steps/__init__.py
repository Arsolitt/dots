"""Step discovery and plan resolution."""

from __future__ import annotations

import importlib
import pkgutil
import re
from dataclasses import dataclass, field
from typing import Callable, Iterable, Sequence

from ..cli import Context

STEP_PATTERN = re.compile(r"s\d+_.+")


@dataclass(frozen=True)
class Step:
    name: str
    title: str
    requires: tuple[str, ...] = ()
    run: Callable[[Context], None] | None = field(default=None, compare=False)


PlanRow = tuple[Step, bool, str]


def discover() -> list[Step]:
    """Import every ``sNN_*.py`` step module and return their STEP objects.

    A package without step modules yields an empty list.
    """
    found: list[Step] = []
    names = sorted(
        module.name
        for module in pkgutil.iter_modules(__path__)
        if STEP_PATTERN.fullmatch(module.name)
    )
    for name in names:
        module = importlib.import_module(f"{__name__}.{name}")
        step = getattr(module, "STEP", None)
        if step is not None:
            found.append(step)
    return found


def plan(
    steps: Iterable[Step],
    ctx: Context,
    only: Sequence[str] = (),
    skip: Sequence[str] = (),
) -> list[PlanRow]:
    """Return ``(step, should_run, reason)`` for every discovered step."""
    only_set = set(only)
    skip_set = set(skip)
    rows: list[PlanRow] = []
    for step in steps:
        if only_set and step.name not in only_set:
            rows.append((step, False, "not selected"))
            continue
        if step.name in skip_set:
            rows.append((step, False, "skipped by flag"))
            continue
        missing = next(
            (feature for feature in step.requires if not ctx.feature(feature)),
            None,
        )
        if missing is not None:
            rows.append((step, False, f"requires {missing}"))
            continue
        rows.append((step, True, ""))
    return rows
