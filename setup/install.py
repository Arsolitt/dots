#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Idempotent dotfiles installer for Arch-derived Linux."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from dotfiles import cli, detect, profile as profiles, steps as stepmod


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="install.py",
        description="Idempotent dotfiles installer for Arch-derived Linux.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print planned actions without changing anything",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="NAME",
        help="run only the named step (repeatable)",
    )
    parser.add_argument(
        "--skip",
        action="append",
        default=[],
        metavar="NAME",
        help="skip the named step (repeatable)",
    )
    parser.add_argument(
        "--profile",
        metavar="PATH",
        help="machine-local profile to apply on top of the device profile",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="overwrite existing files instead of backing them up",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="print the detected host, features and step plan, then exit",
    )
    return parser


def _print_plan(ctx: cli.Context, device: detect.Device, distro: str,
                profile_path: Path | None, overrides: dict[str, str],
                rows: list[tuple[stepmod.Step, bool, str]]) -> None:
    ctx.log_info("dotfiles installer")
    ctx.log_info(f"host: {device.hostname}")
    ctx.log_info(f"distro: {distro}")
    ctx.log_info(f"chassis: {device.chassis}")
    detected = ", ".join(
        f"{name}={str(value).lower()}" for name, value in sorted(device.detected.items())
    )
    ctx.log_info(f"detected: {detected or 'none'}")
    ctx.log_info(f"profile: {profile_path if profile_path else 'none'}")
    override_line = ", ".join(
        f"{name}={value}" for name, value in sorted(overrides.items())
    )
    ctx.log_info(f"overrides: {override_line or 'none'}")
    features = ", ".join(
        f"{name}={str(value).lower()}" for name, value in sorted(ctx.features.items())
    )
    ctx.log_info(f"features: {features or 'none'}")
    if not rows:
        ctx.log_skip("no steps discovered")
        return
    for step, should_run, reason in rows:
        verb = "run " if should_run else "skip"
        line = f"{verb} {step.name}  {step.title}"
        if reason:
            line = f"{line}  ({reason})"
        ctx.log_info(line)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(__file__).resolve().parent.parent

    try:
        distro = detect.check_host()
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

    rows = stepmod.plan(stepmod.discover(), ctx, args.only, args.skip)
    _print_plan(
        ctx,
        device,
        distro,
        profiles.path(root, device.hostname, args.profile),
        loaded.features,
        rows,
    )

    if args.list:
        return 0

    for step, should_run, _reason in rows:
        if not should_run:
            continue
        ctx.log_info(f"step: {step.title}")
        try:
            if step.run is not None:
                step.run(ctx)
        except Exception as exc:  # noqa: BLE001 - one bad step must not stop the rest
            ctx.log_err(f"{step.name}: {exc}")

    ctx.log_info(f"done: {len(ctx.errors)} error(s)")
    return 1 if ctx.errors else 0


if __name__ == "__main__":
    sys.exit(main())
