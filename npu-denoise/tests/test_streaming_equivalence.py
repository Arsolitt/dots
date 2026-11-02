# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "openvino>=2026.4"]
# ///
"""Checks that the streaming host reproduces the exported DeepFilterNet3 graphs.

Run with: ``uv run tests/test_streaming_equivalence.py``.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import openvino as ov

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import dfn  # noqa: E402


def _test_signal(frames: int) -> np.ndarray:
    rng = np.random.default_rng(7)
    t = np.arange(frames * dfn.HOP_SIZE) / dfn.SR
    speech = 0.2 * np.sin(2 * np.pi * 220.0 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 3.0 * t))
    noise = 0.05 * rng.standard_normal(t.size)
    return (speech + noise).astype(np.float32)


def _capture(stream: dfn.DfnStream) -> dict[str, list[dict[str, np.ndarray]]]:
    captured: dict[str, list[dict[str, np.ndarray]]] = {}
    for name, graph in stream._graphs.items():
        run = graph.run

        def recording_run(feeds: dict[str, np.ndarray], *, _name=name, _run=run):
            output = _run(feeds)
            captured.setdefault(_name, []).append(output)
            return output

        graph.run = recording_run
    return captured


def test_streaming_matches_batch_models() -> None:
    models = dfn.MODELS_DIR
    audio = _test_signal(160)
    stream = dfn.DfnStream("CPU", models)
    captured = _capture(stream)
    features, spec_features = [], []
    for frame_index in range(audio.size // dfn.HOP_SIZE):
        stream.process(audio[frame_index * dfn.HOP_SIZE : (frame_index + 1) * dfn.HOP_SIZE])
        features.append(stream._feat_erb[-1])
        spec_features.append(stream._feat_spec[-1])
    stream_mask = np.stack([entry["m"].reshape(-1) for entry in captured["erb_dec"]])
    stream_coefs = np.stack(
        [
            (gru[stream._graphs["df_gru"].extra] + conv[stream._graphs["df_conv"].extra][:, -1:])
            .reshape(dfn.NB_DF, dfn.DF_ORDER, 2)
            for gru, conv in zip(captured["df_gru"], captured["df_conv"])
        ]
    )

    core = ov.Core()
    encoder = core.compile_model(core.read_model(str(models / "enc.onnx")), "CPU")
    encoded = encoder(
        {
            "feat_erb": np.stack(features)[None, None],
            "feat_spec": np.stack(spec_features, axis=1)[None],
        }
    )
    codec = core.compile_model(core.read_model(str(models / "erb_dec.onnx")), "CPU")
    mask = codec(
        {
            "emb": np.array(encoded["emb"], copy=True),
            "e3": np.array(encoded["e3"], copy=True),
            "e2": np.array(encoded["e2"], copy=True),
            "e1": np.array(encoded["e1"], copy=True),
            "e0": np.array(encoded["e0"], copy=True),
        }
    )["m"]
    decoder = core.compile_model(core.read_model(str(models / "df_dec.onnx")), "CPU")
    coefs = decoder(
        {"emb": np.array(encoded["emb"], copy=True), "c0": np.array(encoded["c0"], copy=True)}
    )["coefs"]

    batch_mask = np.array(mask, copy=True).reshape(len(features), -1)
    batch_coefs = np.array(coefs, copy=True).reshape(len(features), dfn.NB_DF, dfn.DF_ORDER, 2)
    mask_error = float(np.abs(stream_mask - batch_mask).max())
    coefs_error = float(np.abs(stream_coefs - batch_coefs).max())
    assert mask_error < 1e-5, f"ERB mask diverges from the batch graph: {mask_error}"
    assert coefs_error < 1e-6, f"DF coefficients diverge from the batch graph: {coefs_error}"
    print(f"streaming vs batch: mask max error {mask_error:.2e}, coefs max error {coefs_error:.2e}")


def test_transform_round_trip() -> None:
    stream = dfn.DfnStream("CPU")
    rng = np.random.default_rng(11)
    audio = (0.1 * rng.standard_normal(dfn.HOP_SIZE * 40)).astype(np.float32)
    block = dfn.HOP_SIZE
    recovered = np.concatenate(
        [stream._synthesis(stream._analysis(audio[i : i + block])) for i in range(0, audio.size, block)]
    )
    error = float(np.abs(recovered[block:] - audio[:-block]).max())
    assert error < 1e-3, f"analysis/synthesis round trip is off by {error}"
    print(f"transform round trip: max error {error:.2e}, delay {block} samples")


if __name__ == "__main__":
    test_streaming_matches_batch_models()
    test_transform_round_trip()
    print("ok")
