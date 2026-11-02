#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "openvino>=2026.4"]
# ///
"""Check that the Intel NPU is reachable through OpenVINO.

Compiles a trivial graph, which exercises the NPU compiler and runtime in a
second or two. The full DeepFilterNet graphs take minutes to compile the first
time, so they are opt-in via --dfn.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import numpy as np
import openvino as ov
from openvino import opset13 as ops

MODELS = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "npu-denoise" / "models"


def tiny_model() -> ov.Model:
    param = ops.parameter([1, 4], np.float32, name="x")
    scale = ops.constant(np.array([[2.0]], dtype=np.float32))
    return ov.Model([ops.multiply(param, scale)], [param])


def compile_tiny(core: ov.Core, device: str) -> float:
    started = time.perf_counter()
    compiled = core.compile_model(tiny_model(), device)
    elapsed = time.perf_counter() - started
    out = compiled([np.array([[1.0, 2.0, 3.0, 4.0]], dtype=np.float32)])[compiled.output(0)]
    assert np.allclose(out, [[2.0, 4.0, 6.0, 8.0]]), out
    return elapsed


def compile_dfn(core: ov.Core, device: str) -> None:
    for name in ("enc", "erb_dec", "df_dec"):
        path = MODELS / f"{name}.onnx"
        started = time.perf_counter()
        core.compile_model(core.read_model(path), device)
        print(f"  {name:8s} {time.perf_counter() - started:6.1f} s")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dfn", action="store_true", help="also compile the DeepFilterNet graphs")
    args = parser.parse_args()

    core = ov.Core()
    devices = core.available_devices
    print("openvino :", ov.__version__)
    print("devices  :", devices)
    if "NPU" not in devices:
        print("NPU      : missing (install level-zero-loader intel-npu-driver intel-npu-compiler)")
        return 1

    print("NPU name :", core.get_property("NPU", "FULL_DEVICE_NAME"))
    print("NPU arch :", core.get_property("NPU", "DEVICE_ARCHITECTURE"))
    try:
        elapsed = compile_tiny(core, "NPU")
    except Exception as exc:
        print("NPU      : compile of a trivial graph failed")
        print(str(exc)[:800])
        return 2
    print(f"NPU      : works, trivial graph compiled in {elapsed:.2f} s")

    if args.dfn:
        print("DFN graphs (first compile is slow, later runs use the cache):")
        compile_dfn(core, "NPU")
    return 0


if __name__ == "__main__":
    sys.exit(main())
