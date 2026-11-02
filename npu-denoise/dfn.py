# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "openvino>=2026.4"]
# ///
"""Streaming DeepFilterNet3 inference: numpy DSP plus OpenVINO neural networks.

The DSP is a port of libDF's per-frame implementation (``libDF/src/lib.rs``); the three
ONNX graphs are the very exports libDF runs (``DeepFilterNet/df/scripts/export.py``).
Those graphs carry GRU state internally in tract-pulse, which an OpenVINO graph cannot
do, so every ``GRUSequence`` here gets its hidden state exposed as a graph input/output
and is carried by this module. The encoder additionally has its convolution path and its
GRU path split in two graphs, because the convolutions need two frames of lookback while
the GRU must see exactly one frame per step to reproduce libDF's recurrence.

Audio contract: 48 kHz mono, 10 ms frames, no resampling. The CLI rejects any other sample
rate instead of resampling, averages multichannel input down to mono, and always writes
16 bit PCM.
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import time
import wave
from collections import deque
from pathlib import Path

import numpy as np
import openvino as ov

SR = 48000
FFT_SIZE = 960
HOP_SIZE = 480
FREQ_SIZE = FFT_SIZE // 2 + 1
NB_ERB = 32
NB_DF = 96
DF_ORDER = 5
CONV_LOOKAHEAD = 2
DF_LOOKAHEAD = 2
LOOKAHEAD = max(CONV_LOOKAHEAD, DF_LOOKAHEAD)
MIN_NB_ERB_FREQS = 2
NORM_TAU = 1.0
MEAN_NORM_INIT = (-60.0, -90.0)
UNIT_NORM_INIT = (0.001, 0.0001)
LOG_EPS = 1e-10
ERB_NORM_SCALE = 40.0
MODELS_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "npu-denoise" / "models"


def _freq2erb(freq: float) -> float:
    return 9.265 * math.log1p(freq / (24.7 * 9.265))


def _erb2freq(erb: float) -> float:
    return 24.7 * 9.265 * (math.exp(erb / 9.265) - 1.0)


def _erb_widths() -> np.ndarray:
    """ERB band widths in FFT bins, matching ``libdf::erb_fb``."""
    freq_width = SR / FFT_SIZE
    erb_low = _freq2erb(0.0)
    erb_high = _freq2erb(SR / 2)
    step = (erb_high - erb_low) / NB_ERB
    widths = [0] * NB_ERB
    prev_freq = 0
    freq_over = 0
    for index in range(1, NB_ERB + 1):
        freq = _erb2freq(erb_low + index * step)
        band_end = int(round(freq / freq_width))
        nb_freqs = band_end - prev_freq - freq_over
        if nb_freqs < MIN_NB_ERB_FREQS:
            freq_over = MIN_NB_ERB_FREQS - nb_freqs
            nb_freqs = MIN_NB_ERB_FREQS
        else:
            freq_over = 0
        widths[index - 1] = nb_freqs
        prev_freq = band_end
    widths[-1] += 1
    too_large = sum(widths) - FREQ_SIZE
    if too_large > 0:
        widths[-1] -= too_large
    if sum(widths) != FREQ_SIZE:
        raise RuntimeError(f"ERB filterbank covers {sum(widths)} bins, expected {FREQ_SIZE}")
    return np.array(widths, np.int64)


def _vorbis_window() -> np.ndarray:
    """Vorbis window, matching ``libdf::DFState::new``."""
    positions = np.arange(FFT_SIZE, dtype=np.float64) + 0.5
    inner = np.sin(math.pi * positions / FFT_SIZE)
    return np.sin(0.5 * math.pi * inner * inner).astype(np.float32)


def _norm_alpha() -> float:
    """Smoothing factor of the exponential feature normalisation, matching ``calc_norm_alpha``."""
    alpha = math.exp(-(HOP_SIZE / SR) / NORM_TAU)
    precision = 3
    value = 1.0
    while value >= 1.0:
        scale = 10.0**precision
        value = round(alpha * scale) / scale
        precision += 1
    return value


def _grus(model: ov.Model) -> list[ov.Node]:
    return [op for op in model.get_ordered_ops() if op.get_type_name() == "GRUSequence"]


def _drop_result(model: ov.Model, name: str) -> None:
    for result in list(model.results):
        if result.get_friendly_name().split("/")[0] == name:
            model.remove_result(result)


def _add_result(model: ov.Model, tensor: ov.Output) -> int:
    """Append ``tensor`` as a model output and return its index among the results."""
    before = len(model.results)
    model.add_outputs([tensor])
    if len(model.results) != before + 1:
        raise RuntimeError("adding a graph output did not append a result")
    return before


def _attach_state(model: ov.Model) -> list[list[int]]:
    """Expose each GRU hidden state as a graph input ("state<N>") and output."""
    grus = _grus(model)
    shapes = []
    for index, gru in enumerate(grus):
        shape = [dim.get_length() for dim in gru.get_output_partial_shape(1)]
        param = ov.opset1.parameter(ov.PartialShape(shape), np.float32, name=f"state{index}")
        model.add_parameters([param])
        gru.set_argument(1, param.output(0))
        shapes.append(shape)
    model.add_outputs([gru.output(1) for gru in grus])
    return shapes


class _Runner:
    """Compiled graph with persistent GRU state and per-frame timing."""

    def __init__(
        self,
        model: ov.Model,
        device: str,
        states: list[list[int]],
        extra_output: int | None = None,
    ) -> None:
        model.validate_nodes_and_infer_types()
        self._compiled = ov.Core().compile_model(model, device)
        self.input_names = [port.get_any_name() for port in self._compiled.inputs]
        self.output_names = [port.get_any_name() for port in self._compiled.outputs]
        self._placeholders = {}
        for port in self._compiled.inputs:
            shape = [dim.get_length() if dim.is_static else None for dim in port.get_partial_shape()]
            if any(dim is None for dim in shape):
                raise RuntimeError(f"graph input {port.get_any_name()} is not statically shaped")
            self._placeholders[port.get_any_name()] = np.zeros(shape, np.float32)
        self._state_inputs = [f"state{index}" for index in range(len(states))]
        self._state_outputs = self.output_names[-len(states) :] if states else []
        self._states = [np.zeros(shape, np.float32) for shape in states]
        self.extra = self.output_names[extra_output] if extra_output is not None else None
        self.seconds = 0.0

    def reset(self) -> None:
        for state in self._states:
            state.fill(0.0)

    def run(self, feeds: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
        unknown = set(feeds) - set(self.input_names)
        if unknown:
            raise ValueError(f"unknown graph inputs: {sorted(unknown)}")
        request = dict(feeds)
        for name, state in zip(self._state_inputs, self._states):
            request[name] = state
        for name in self.input_names:
            request.setdefault(name, self._placeholders[name])
        start = time.perf_counter()
        outputs = self._compiled(request)
        self.seconds += time.perf_counter() - start
        result = {name: np.array(outputs[name], copy=True) for name in self.output_names}
        for index, name in enumerate(self._state_outputs):
            self._states[index] = result[name]
        return result


def _pin_time(model: ov.Model, frame_count: int) -> dict[str, list[int]]:
    """Static shapes for every graph input, with the time axis pinned to ``frame_count``."""
    shapes = {}
    for port in model.inputs:
        shapes[port.get_any_name()] = [
            dim.get_length() if dim.is_static else frame_count for dim in port.get_partial_shape()
        ]
    return shapes


def _build_graphs(models_dir: Path, device: str) -> dict[str, _Runner]:
    graphs: dict[str, _Runner] = {}

    front = ov.Core().read_model(str(models_dir / "enc.onnx"))
    front_features = _grus(front)[0].input_value(0)
    _drop_result(front, "emb")
    _drop_result(front, "lsnr")
    front_x = _add_result(front, front_features)
    front.reshape(_pin_time(front, CONV_LOOKAHEAD + 1))
    graphs["enc_conv"] = _Runner(front, device, [], extra_output=front_x)

    back = ov.Core().read_model(str(models_dir / "enc.onnx"))
    for name in ("e0", "e1", "e2", "e3", "c0"):
        _drop_result(back, name)
    back_gru = _grus(back)[0]
    features = ov.opset1.parameter(
        ov.PartialShape([1, 1, back_gru.get_input_partial_shape(3)[-1].get_length()]),
        np.float32,
        name="x",
    )
    back.add_parameters([features])
    back_gru.set_argument(0, features.output(0))
    back_states = _attach_state(back)
    back.reshape(_pin_time(back, 1))
    graphs["enc_gru"] = _Runner(back, device, back_states)

    erb_decoder = ov.Core().read_model(str(models_dir / "erb_dec.onnx"))
    erb_states = _attach_state(erb_decoder)
    erb_decoder.reshape(_pin_time(erb_decoder, 1))
    graphs["erb_dec"] = _Runner(erb_decoder, device, erb_states)

    gru_only = ov.Core().read_model(str(models_dir / "df_dec.onnx"))
    gru_sum = _coef_sum_node(gru_only)
    _drop_result(gru_only, "coefs")
    _drop_result(gru_only, "235")
    df_gru_out = _add_result(gru_only, gru_sum.input_value(0))
    df_states = _attach_state(gru_only)
    gru_only.reshape(_pin_time(gru_only, 1))
    graphs["df_gru"] = _Runner(gru_only, device, df_states, extra_output=df_gru_out)

    conv_only = ov.Core().read_model(str(models_dir / "df_dec.onnx"))
    conv_sum = _coef_sum_node(conv_only)
    _drop_result(conv_only, "coefs")
    _drop_result(conv_only, "235")
    df_conv_out = _add_result(conv_only, conv_sum.input_value(1))
    conv_only.reshape(_pin_time(conv_only, DF_ORDER))
    graphs["df_conv"] = _Runner(conv_only, device, [], extra_output=df_conv_out)
    return graphs


def _coef_sum_node(model: ov.Model) -> ov.Node:
    """The node adding the DF decoder's GRU branch and its c0 branch."""
    result = next(r for r in model.results if r.get_friendly_name().startswith("coefs"))
    node = result.input_value(0).get_node()
    if node.get_type_name() != "Add":
        raise RuntimeError(f"unexpected coefs assembly node {node.get_type_name()}")
    return node


class DfnStream:
    """Streaming DeepFilterNet3 on 10 ms frames, one channel at 48 kHz."""

    def __init__(self, device: str = "CPU", models_dir: Path | str = MODELS_DIR) -> None:
        self.device = device
        self.models_dir = Path(models_dir)
        self._graphs = _build_graphs(self.models_dir, device)
        self._window = _vorbis_window()
        self._erb_widths = _erb_widths()
        self._alpha = _norm_alpha()
        self._wnorm = 2 * HOP_SIZE / (FFT_SIZE**2)
        self._erb_starts = np.concatenate(([0], np.cumsum(self._erb_widths)[:-1]))
        self.frames = 0
        self._dsp_seconds = 0.0
        self.reset()

    def reset(self) -> None:
        for graph in self._graphs.values():
            graph.reset()
        self._analysis_mem = np.zeros(HOP_SIZE, np.float32)
        self._synthesis_mem = np.zeros(HOP_SIZE, np.float32)
        self._erb_state = np.linspace(*MEAN_NORM_INIT, NB_ERB).astype(np.float32)
        self._unit_state = np.linspace(*UNIT_NORM_INIT, NB_DF).astype(np.float32)
        self._spec_y: deque[np.ndarray] = deque(
            (np.zeros(FREQ_SIZE, np.complex64) for _ in range(DF_ORDER + CONV_LOOKAHEAD)),
            maxlen=DF_ORDER + CONV_LOOKAHEAD,
        )
        self._spec_x: deque[np.ndarray] = deque(
            (np.zeros(FREQ_SIZE, np.complex64) for _ in range(max(LOOKAHEAD, DF_ORDER))),
            maxlen=max(LOOKAHEAD, DF_ORDER),
        )
        self._feat_erb: deque[np.ndarray] = deque(
            (np.zeros(NB_ERB, np.float32) for _ in range(CONV_LOOKAHEAD + 1)),
            maxlen=CONV_LOOKAHEAD + 1,
        )
        self._feat_spec: deque[np.ndarray] = deque(
            (np.zeros((2, NB_DF), np.float32) for _ in range(CONV_LOOKAHEAD + 1)),
            maxlen=CONV_LOOKAHEAD + 1,
        )
        self._c0: deque[np.ndarray] = deque(
            (np.zeros((64, NB_DF), np.float32) for _ in range(DF_ORDER)),
            maxlen=DF_ORDER,
        )

    def process(self, frame: np.ndarray) -> np.ndarray:
        """Consume ``HOP_SIZE`` input samples and return ``HOP_SIZE`` enhanced samples.

        The returned block is the enhancement of the input ``LOOKAHEAD + 1`` frames earlier,
        i.e. the pipeline delays audio by 30 ms; ``denoise`` compensates for it.
        """
        frame = np.asarray(frame, dtype=np.float32).reshape(-1)
        if frame.size != HOP_SIZE:
            raise ValueError(f"expected {HOP_SIZE} samples per frame, got {frame.size}")
        start = time.perf_counter()
        spec = self._analysis(frame)
        self._spec_y.append(spec)
        self._spec_x.append(spec)
        erb_feat, spec_feat = self._features(spec)
        self._feat_erb.append(erb_feat)
        self._feat_spec.append(spec_feat)
        feeds_erb = np.stack(self._feat_erb)[None, None]
        feeds_spec = np.stack(self._feat_spec, axis=1)[None]
        self._dsp_seconds += time.perf_counter() - start

        enc_conv = self._graphs["enc_conv"]
        conv = enc_conv.run({"feat_erb": feeds_erb, "feat_spec": feeds_spec})
        self._c0.append(conv["c0"][0, :, -1, :])
        activations = {name: conv[name][:, :, -1:, :] for name in ("e0", "e1", "e2", "e3")}
        embedding = self._graphs["enc_gru"].run({"x": conv[enc_conv.extra][:, -1:, :]})["emb"]

        mask = self._graphs["erb_dec"].run({"emb": embedding, **activations})["m"]
        coefs = self._graphs["df_gru"].run({"emb": embedding})[self._graphs["df_gru"].extra]
        c0_window = np.stack(self._c0, axis=1)[None]
        conv_coefs = self._graphs["df_conv"].run({"c0": c0_window})[self._graphs["df_conv"].extra]
        coefs = coefs + conv_coefs[:, -1:, :, :]

        start = time.perf_counter()
        gains = np.repeat(mask.reshape(NB_ERB), self._erb_widths)
        enhanced = self._spec_y[DF_ORDER - 1] * gains
        enhanced[:NB_DF] = _deep_filter(self._spec_x, coefs.reshape(NB_DF, DF_ORDER, 2))
        output = self._synthesis(enhanced)
        self._dsp_seconds += time.perf_counter() - start
        return output

    def timings(self) -> dict[str, float]:
        """Mean milliseconds per processed frame for every graph, the DSP, and the total."""
        if self.frames == 0:
            return {}
        divisor = self.frames / 1000.0
        timings = {name: graph.seconds / divisor for name, graph in self._graphs.items()}
        timings["dsp"] = self._dsp_seconds / divisor
        timings["total"] = sum(timings.values())
        return timings

    def _analysis(self, frame: np.ndarray) -> np.ndarray:
        buffer = np.empty(FFT_SIZE, np.float32)
        np.multiply(self._analysis_mem, self._window[:HOP_SIZE], out=buffer[:HOP_SIZE])
        np.multiply(frame, self._window[HOP_SIZE:], out=buffer[HOP_SIZE:])
        np.copyto(self._analysis_mem, frame)
        self.frames += 1
        spectrum = np.fft.rfft(buffer) * self._wnorm
        return spectrum.astype(np.complex64)

    def _synthesis(self, spectrum: np.ndarray) -> np.ndarray:
        block = np.fft.irfft(spectrum, FFT_SIZE) * FFT_SIZE * self._window
        output = block[:HOP_SIZE] + self._synthesis_mem
        np.copyto(self._synthesis_mem, block[HOP_SIZE:])
        return output.astype(np.float32)

    def _features(self, spec: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        power = spec.real * spec.real + spec.imag * spec.imag
        erb = np.add.reduceat(power, self._erb_starts) / self._erb_widths
        erb_db = 10.0 * np.log10(erb + LOG_EPS)
        self._erb_state = erb_db * (1.0 - self._alpha) + self._erb_state * self._alpha
        erb_feat = (erb_db - self._erb_state) / ERB_NORM_SCALE

        complex_part = spec[:NB_DF]
        self._unit_state = (
            np.abs(complex_part) * (1.0 - self._alpha) + self._unit_state * self._alpha
        )
        normalised = complex_part / np.sqrt(self._unit_state)
        spec_feat = np.stack((normalised.real, normalised.imag)).astype(np.float32)
        return erb_feat.astype(np.float32), spec_feat


def _deep_filter(history: deque[np.ndarray], coefs: np.ndarray) -> np.ndarray:
    """Deep filtering of the low ``NB_DF`` bins over the last ``DF_ORDER`` spectra."""
    output = np.zeros(NB_DF, np.complex64)
    for index in range(DF_ORDER):
        taps = (coefs[:, index, 0] + 1j * coefs[:, index, 1]).astype(np.complex64)
        output += history[index][:NB_DF] * taps
    return output


def _read_wav(path: Path) -> tuple[np.ndarray, int]:
    """Decode a RIFF/WAVE file to float32 mono. Integer and IEEE-float PCM are supported."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path} is not a RIFF/WAVE file")
    chunks: dict[bytes, bytes] = {}
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset : offset + 4]
        size = struct.unpack("<I", data[offset + 4 : offset + 8])[0]
        chunks.setdefault(chunk_id, data[offset + 8 : offset + 8 + size])
        offset += 8 + size + (size & 1)
    if b"fmt " not in chunks or b"data" not in chunks:
        raise ValueError(f"{path} is missing a fmt or data chunk")
    fmt = chunks[b"fmt "]
    tag, channels, sample_rate, _, block_align, bits = struct.unpack("<HHIIHH", fmt[:16])
    if tag == 0xFFFE and len(fmt) >= 26:
        tag = struct.unpack("<H", fmt[24:26])[0]
    payload = chunks[b"data"]
    width = bits // 8
    if width * channels != block_align:
        raise ValueError(f"{path} has an unsupported block alignment {block_align}")
    if tag == 3:
        samples = np.frombuffer(payload, dtype="<f4" if bits == 32 else "<f8").astype(np.float32)
    elif tag == 1 and bits == 8:
        samples = (np.frombuffer(payload, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif tag == 1 and bits == 16:
        samples = np.frombuffer(payload, dtype="<i2").astype(np.float32) / 32768.0
    elif tag == 1 and bits == 24:
        raw = np.frombuffer(payload, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        merged = raw[:, 0] | (raw[:, 1] << 8) | (raw[:, 2] << 16)
        samples = ((merged << 8) >> 8).astype(np.float32) / 8388608.0
    elif tag == 1 and bits == 32:
        samples = np.frombuffer(payload, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"{path}: unsupported WAV encoding (format {tag}, {bits} bit)")
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples.astype(np.float32), sample_rate


def _write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.rint(np.clip(samples, -1.0, 1.0) * 32767.0)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.astype("<i2").tobytes())


def denoise(samples: np.ndarray, stream: DfnStream) -> np.ndarray:
    """Stream a whole buffer through ``stream`` and drop the pipeline's algorithmic delay."""
    frames = samples.size // HOP_SIZE
    tail = samples[frames * HOP_SIZE :]
    blocks = []
    for index in range(frames + (1 if tail.size else 0)):
        block = samples[index * HOP_SIZE : (index + 1) * HOP_SIZE]
        if block.size < HOP_SIZE:
            block = np.pad(block, (0, HOP_SIZE - block.size))
        blocks.append(stream.process(block))
    for _ in range(LOOKAHEAD + 1):
        blocks.append(stream.process(np.zeros(HOP_SIZE, np.float32)))
    return np.concatenate(blocks)[(LOOKAHEAD + 1) * HOP_SIZE :][: samples.size]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Denoise a 48 kHz mono WAV with DeepFilterNet3.")
    parser.add_argument(
        "--in",
        dest="source",
        required=True,
        help="input WAV; must be 48 kHz (not resampled), channels are mixed down to mono",
    )
    parser.add_argument("--out", dest="target", required=True, help="output WAV, 16 bit PCM")
    parser.add_argument("--device", default="CPU", help="OpenVINO device, e.g. CPU or NPU")
    parser.add_argument("--models", default=str(MODELS_DIR), help="ONNX export directory")
    args = parser.parse_args(argv)

    samples, sample_rate = _read_wav(Path(args.source))
    if sample_rate != SR:
        parser.error(f"input is {sample_rate} Hz, DeepFilterNet3 needs {SR} Hz; resample first")
    stream = DfnStream(args.device, Path(args.models))
    start = time.perf_counter()
    enhanced = denoise(samples, stream)
    wall = time.perf_counter() - start
    _write_wav(Path(args.target), enhanced)

    timings = stream.timings()
    duration = samples.size / SR
    print(f"device {args.device}, {stream.frames} frames ({duration:.2f} s of audio)")
    for name, value in timings.items():
        print(f"  {name:>9}: {value:6.3f} ms/frame")
    print(
        f"  total per frame: {timings['total']:.3f} ms "
        f"({timings['total'] / (HOP_SIZE / SR * 1000):.2f}x realtime), wall {wall:.2f} s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
