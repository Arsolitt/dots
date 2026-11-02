"""Deploy the loopback-only SearXNG docker compose stack."""

from __future__ import annotations

import filecmp
import secrets
import shutil
from pathlib import Path

from ..cli import Context
from . import Step

PLACEHOLDER = "__SEARXNG_SECRET__"
CONTAINER = "searxng"


def _copy_compose(ctx: Context, source: Path, target: Path) -> None:
    if target.is_file() and filecmp.cmp(source, target, shallow=False):
        ctx.log_skip("searxng: compose file up to date")
        return
    exists = target.is_file()
    if ctx.dry_run:
        action = "update" if exists else "install"
        ctx.log_info(f"would {action} {target} from {source}")
        return
    shutil.copyfile(source, target)
    ctx.log_ok(
        f"searxng: compose file {'updated' if exists else 'installed'} at {target}"
    )


def _render_settings(ctx: Context, template: Path, target: Path) -> None:
    if target.is_file():
        current = target.read_text(encoding="utf-8")
        if PLACEHOLDER not in current:
            ctx.log_skip("searxng: settings.yml already has a secret_key")
            return
        base = current
    else:
        base = template.read_text(encoding="utf-8")

    if ctx.dry_run:
        ctx.log_info(f"would render {target} with a generated secret_key")
        return

    secret = secrets.token_hex(32)
    target.write_text(base.replace(PLACEHOLDER, secret), encoding="utf-8")
    ctx.log_ok(f"searxng: settings.yml rendered at {target}")


def _run(ctx: Context) -> None:
    if not ctx.have("docker"):
        ctx.log_skip("searxng: docker is not installed")
        return

    source_dir = ctx.root / "searxng"
    source_compose = source_dir / "docker-compose.yml"
    source_template = source_dir / "settings.yml.template"
    if not source_compose.is_file() or not source_template.is_file():
        ctx.log_err(f"searxng: repo assets missing under {source_dir}")
        return

    target = Path.home() / "docker" / "searxng"
    settings_dir = target / "searxng"
    ctx.ensure_dir(target)
    ctx.ensure_dir(settings_dir)

    _copy_compose(ctx, source_compose, target / "docker-compose.yml")
    _render_settings(ctx, source_template, settings_dir / "settings.yml")

    if not ctx.dry_run and not ctx.ok(["docker", "info"]):
        ctx.log_warn("searxng: docker not reachable — relogin, then re-run install.py")
        return

    running = ctx.capture(
        ["docker", "inspect", "-f", "{{.State.Running}}", CONTAINER]
    )
    if (running or "").strip() == "true":
        ctx.log_skip("searxng: container already running")
        return

    before = len(ctx.errors)
    ctx.run(
        ["docker", "compose", "-f", str(target / "docker-compose.yml"), "up", "-d"],
        cwd=target,
    )
    if not ctx.dry_run and len(ctx.errors) == before:
        ctx.log_ok("searxng: stack up on http://127.0.0.1:8080")


STEP = Step(
    name="searxng",
    title="deploy the local SearXNG stack",
    requires=("docker",),
    run=_run,
)
