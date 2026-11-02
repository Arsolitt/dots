#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Link-only dotfiles installer for Arch-derived Linux."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from dotfiles import cli, detect, links as linker, profile as profiles, steps as stepmod


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="links.py",
        description="Symlink dotfiles into $HOME without running the full install.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print planned actions without changing anything",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="overwrite existing files instead of backing them up",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="remove broken dotfiles symlinks, then exit",
    )
    parser.add_argument(
        "--profile",
        metavar="PATH",
        help="machine-local profile to apply on top of the device profile",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(__file__).resolve().parent.parent

    try:
        detect.check_host()
    except detect.UnsupportedHost as exc:
        print(f"unsupported OS: {exc}", file=sys.stderr)
        return 2

    ctx = cli.Context(
        root=root,
        dry_run=args.dry_run,
        assume_yes=False,
        no_backup=args.no_backup,
        features={},
        errors=[],
    )
    device = detect.device()
    try:
        loaded = profiles.load(root, device.hostname, args.profile)
        ctx.features = profiles.resolve(device.detected, loaded)
        ctx.profile = loaded
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    ctx.log_info("dotfiles links")
    ctx.log_info(f"host: {device.hostname} ({device.chassis})")

    link = linker.Linker(ctx, root, backup=not args.no_backup)
    if args.cleanup:
        link.cleanup(linker.DEFAULT_SCAN_DIRS)
        ctx.log_info(f"done: {len(ctx.errors)} error(s)")
        return 1 if ctx.errors else 0

    configs = next(
        (step for step in stepmod.discover() if step.name == "configs"),
        None,
    )
    if configs is None:
        ctx.log_skip("configs step not installed yet")
        return 1 if ctx.errors else 0

    try:
        configs.run(ctx)
    except Exception as exc:  # noqa: BLE001 - report and exit non-zero
        ctx.log_err(f"{configs.name}: {exc}")

    ctx.log_info(f"done: {len(ctx.errors)} error(s)")
    return 1 if ctx.errors else 0


if __name__ == "__main__":
    sys.exit(main())
