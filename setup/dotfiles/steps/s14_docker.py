"""Enable the docker service and grant the user group access."""

from __future__ import annotations

import os
import pwd

from ..cli import Context
from . import Step


def _already(ctx: Context, args: list[str]) -> bool:
    """Probe a guard in real runs; dry-run plans the action instead."""
    return not ctx.dry_run and ctx.ok(args)


def _groups(ctx: Context) -> set[str]:
    return set(ctx.read(["id", "-nG"]).split())


def _user() -> str:
    return os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name


def _run(ctx: Context) -> None:
    if not ctx.have("systemctl"):
        ctx.log_warn("docker: systemctl not available — start docker manually")
        return

    if _already(ctx, ["systemctl", "is-enabled", "--quiet", "docker"]):
        ctx.log_skip("docker: service already enabled")
    else:
        ctx.run(["systemctl", "enable", "docker"], sudo=True)

    if _already(ctx, ["systemctl", "is-active", "--quiet", "docker"]):
        ctx.log_skip("docker: service already running")
    else:
        ctx.run(["systemctl", "start", "docker"], sudo=True)

    user = _user()
    if "docker" in _groups(ctx):
        ctx.log_skip("docker: user already in the docker group")
    else:
        before = len(ctx.errors)
        ctx.run(["usermod", "-aG", "docker", user], sudo=True)
        if not ctx.dry_run and len(ctx.errors) == before:
            ctx.log_warn(
                f"docker: added {user} to the docker group — relogin required "
                "for rootless CLI access"
            )


STEP = Step(name="docker", title="enable docker service and group access", run=_run)
