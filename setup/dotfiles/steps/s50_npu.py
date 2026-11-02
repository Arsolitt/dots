"""NPU denoiser: render group access and DeepFilterNet model download."""

from __future__ import annotations

import os
import pwd
from pathlib import Path

from ..cli import Context
from . import Step

RENDER_GROUP = "render"
MODEL_FILES = ("enc.onnx", "erb_dec.onnx", "df_dec.onnx")


def _user() -> str:
    return os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name


def _models_dir() -> Path:
    cache = os.environ.get("XDG_CACHE_HOME")
    base = Path(cache).expanduser() if cache else Path.home() / ".cache"
    return base / "npu-denoise" / "models"


def _groups(ctx: Context) -> set[str]:
    return set(ctx.read(["id", "-nG"]).split())


def _ensure_render_group(ctx: Context) -> None:
    if not ctx.ok(["getent", "group", RENDER_GROUP]):
        ctx.log_warn(f"npu: no {RENDER_GROUP} group — install intel-npu-driver first")
        return

    if RENDER_GROUP in _groups(ctx):
        ctx.log_skip(f"npu: user already in the {RENDER_GROUP} group")
        return

    user = _user()
    ctx.run(["usermod", "-aG", RENDER_GROUP, user], sudo=True)
    ctx.log_warn(
        f"npu: added {user} to the {RENDER_GROUP} group — relogin before using the NPU"
    )


def _ensure_models(ctx: Context) -> None:
    models = _models_dir()
    if all((models / name).is_file() for name in MODEL_FILES):
        ctx.log_skip(f"npu: models present in {models}")
        return

    script = ctx.root / "npu-denoise" / "scripts" / "fetch-models.sh"
    if not script.is_file():
        ctx.log_err(f"npu: missing model fetch script {script}")
        return
    ctx.run(["bash", script])


def _run(ctx: Context) -> None:
    ctx.log_info("npu: checking render group and DeepFilterNet models")
    _ensure_render_group(ctx)
    _ensure_models(ctx)


STEP = Step(
    name="npu",
    title="grant render access and fetch NPU denoiser models",
    requires=("npu",),
    run=_run,
)
