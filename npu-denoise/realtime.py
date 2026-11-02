# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "openvino>=2026.4"]
# ///
"""Live microphone denoising through PipeWire.

Two ``pw-cat`` children carry raw float32 48 kHz PCM: one records the physical source at
its native width, one plays the enhanced mono stream into a sink
(``scripts/virtual-source.sh`` turns that sink into ``npu_mic``). The reader thread picks the
configured capsule out of every interleaved payload, pushes the mono frames into a bounded
queue, and the main loop denoises them, runs the post chain and writes them to the playback
child, dropping frames instead of growing latency when playback falls behind.

Recording the source at its native width matters: asking ``pw-cat`` for fewer channels than
the device exposes makes PipeWire fold the capsules together, and capsules that are separated
in space sum with a delay into comb notches, which is heard as a hollow, bucket-like timbre.

Usage:
    .venv/bin/python realtime.py --source alsa_input...HiFi__Mic1__source --sink npu_denoise
"""

from __future__ import annotations

import argparse
import io
import math
import queue
import signal
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np

import dfn

CAPTURE_CHANNELS = 4
CAPSULE = 0
FRAME_BYTES = dfn.HOP_SIZE * 4 * CAPTURE_CHANNELS
FRAME_MS = dfn.HOP_SIZE / dfn.SR * 1000.0
STATS_INTERVAL = 10.0
WINDOW = 60.0


def _node_names(kind: str) -> dict[str, str]:
    """Map both the id and the name of every PipeWire node of ``kind`` to its name.

    ``pw-cat`` silently falls back to the default device when ``--target`` does not match,
    which would record the wrong microphone or play into the speakers.
    """
    listing = subprocess.run(
        ["pactl", "list", "short", kind], capture_output=True, text=True, check=True
    ).stdout
    nodes: dict[str, str] = {}
    for line in listing.splitlines():
        fields = line.split("\t")
        if len(fields) >= 2:
            nodes[fields[0]] = fields[1]
            nodes[fields[1]] = fields[1]
    return nodes


def _require_node(kind: str, target: str, parser: argparse.ArgumentParser) -> None:
    nodes = _node_names(kind)
    if target not in nodes:
        available = ", ".join(sorted(set(nodes.values())))
        parser.error(f"no {kind[:-1]} {target!r}; available: {available}")


def _capture_command(source: str) -> list[str]:
    return [
        "pw-cat",
        "--record",
        "--raw",
        "--format",
        "f32",
        "--rate",
        str(dfn.SR),
        "--channels",
        str(CAPTURE_CHANNELS),
        "--target",
        source,
        "-",
    ]


def _playback_command(sink: str) -> list[str]:
    return [
        "pw-cat",
        "--playback",
        "--raw",
        "--format",
        "f32",
        "--rate",
        str(dfn.SR),
        "--channels",
        "1",
        "--target",
        sink,
        "-",
    ]


class _Pump(threading.Thread):
    """Reads fixed-size capture frames and hands one capsule of each to the bounded queue."""

    def __init__(
        self,
        stream: io.BufferedReader,
        frames: queue.Queue[np.ndarray],
        stop: threading.Event,
        capsule: int,
    ) -> None:
        super().__init__(name="capture", daemon=True)
        self._stream = stream
        self._frames = frames
        self._stop = stop
        self._capsule = capsule
        self.dropped = 0

    def run(self) -> None:
        while not self._stop.is_set():
            payload = self._stream.read(FRAME_BYTES)
            if len(payload) < FRAME_BYTES:
                self._stop.set()
                return
            block = np.frombuffer(payload, dtype=np.float32).reshape(-1, CAPTURE_CHANNELS)
            frame = block[:, self._capsule].copy()
            try:
                self._frames.put_nowait(frame)
            except queue.Full:
                self.dropped += 1


class PostChain:
    """DC blocker, 80 Hz high-pass and peak limiter for the denoised mono stream.

    The physical microphone carries a large sub-100 Hz rumble, and DeepFilterNet leaves that
    band nearly untouched, so the stream that reaches a listener is dominated by low
    frequency energy that reads as a boomy, hollow timbre and costs headroom. The high-pass
    removes it; the limiter keeps the gain the browser applies afterwards from clipping.
    """

    HPF_HZ = 80.0
    HPF_Q = 1.0 / math.sqrt(2.0)
    DC_POLE = 0.995
    CEILING = 0.891
    ATTACK_MS = 5.0
    RELEASE_MS = 50.0

    def __init__(self, rate: int = dfn.SR) -> None:
        w0 = 2.0 * math.pi * self.HPF_HZ / rate
        cos_w0 = math.cos(w0)
        alpha = math.sin(w0) / (2.0 * self.HPF_Q)
        a0 = 1.0 + alpha
        self._b0 = (1.0 + cos_w0) / 2.0 / a0
        self._b1 = -(1.0 + cos_w0) / a0
        self._b2 = self._b0
        self._a1 = -2.0 * cos_w0 / a0
        self._a2 = (1.0 - alpha) / a0
        self._x1 = 0.0
        self._x2 = 0.0
        self._y1 = 0.0
        self._y2 = 0.0
        self._dc_in = 0.0
        self._dc_out = 0.0
        self._gain = 1.0
        self._attack = math.exp(-1.0 / (self.ATTACK_MS * 1e-3 * rate))
        self._release = math.exp(-1.0 / (self.RELEASE_MS * 1e-3 * rate))

    def process(self, frame: np.ndarray) -> np.ndarray:
        out = np.empty(frame.shape, dtype=np.float32)
        b0, b1, b2 = self._b0, self._b1, self._b2
        a1, a2 = self._a1, self._a2
        pole = self.DC_POLE
        ceiling = self.CEILING
        attack, release = self._attack, self._release
        x1, x2, y1, y2 = self._x1, self._x2, self._y1, self._y2
        dc_in, dc_out = self._dc_in, self._dc_out
        gain = self._gain
        for index, sample in enumerate(frame):
            value = float(sample)
            dc_out = value - dc_in + pole * dc_out
            dc_in = value
            filtered = b0 * dc_out + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1 = x1, dc_out
            y2, y1 = y1, filtered
            magnitude = -filtered if filtered < 0.0 else filtered
            target = ceiling / magnitude if magnitude > ceiling else 1.0
            coefficient = attack if target < gain else release
            gain = target + (gain - target) * coefficient
            limited = filtered * gain
            if limited > ceiling:
                limited = ceiling
            elif limited < -ceiling:
                limited = -ceiling
            out[index] = limited
        self._x1, self._x2, self._y1, self._y2 = x1, x2, y1, y2
        self._dc_in, self._dc_out = dc_in, dc_out
        self._gain = gain
        return out


class Realtime:
    def __init__(self, device: str, source: str, sink: str, models: Path, backlog: int) -> None:
        self._stream = dfn.DfnStream(device, models)
        self._frames: queue.Queue[np.ndarray] = queue.Queue(maxsize=backlog)
        self._stop = threading.Event()
        self._source = source
        self._sink = sink
        self._backlog = backlog
        self._costs: deque[tuple[float, float]] = deque()
        self._processed = 0
        self._pump: _Pump | None = None
        self._post = PostChain()

    def stop(self) -> None:
        self._stop.set()

    def run(self) -> int:
        capture = subprocess.Popen(
            _capture_command(self._source),
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            bufsize=0,
        )
        playback = subprocess.Popen(
            _playback_command(self._sink),
            stdin=subprocess.PIPE,
            stderr=sys.stderr,
            bufsize=0,
        )
        assert capture.stdout is not None and playback.stdin is not None
        pump = _Pump(
            io.BufferedReader(capture.stdout, buffer_size=FRAME_BYTES * 4),
            self._frames,
            self._stop,
            CAPSULE,
        )
        self._pump = pump
        pump.start()
        print(f"capture {self._source} -> denoise ({self._stream.device}) -> playback {self._sink}")
        print(f"queue limit {self._backlog} frames, {FRAME_MS:.0f} ms per frame; Ctrl-C to stop")

        next_stats = time.monotonic() + STATS_INTERVAL
        try:
            while not self._stop.is_set():
                try:
                    frame = self._frames.get(timeout=0.2)
                except queue.Empty:
                    if capture.poll() is not None or playback.poll() is not None:
                        break
                    continue
                started = time.perf_counter()
                try:
                    enhanced = self._post.process(self._stream.process(frame))
                except RuntimeError:
                    if self._stop.is_set():
                        break
                    raise
                playback.stdin.write(enhanced.tobytes())
                playback.stdin.flush()
                cost = (time.perf_counter() - started) * 1000.0
                now = time.monotonic()
                self._costs.append((now, cost))
                self._processed += 1
                while self._costs and now - self._costs[0][0] > WINDOW:
                    self._costs.popleft()
                if now >= next_stats:
                    self._report(now)
                    next_stats = now + STATS_INTERVAL
        except (BrokenPipeError, KeyboardInterrupt):
            pass
        finally:
            self._stop.set()
            self._shutdown(capture, playback)
            pump.join(timeout=2.0)
        self._report(time.monotonic(), final=True)
        return 0

    def _report(self, now: float, final: bool = False) -> None:
        window = [cost for stamp, cost in self._costs if now - stamp <= WINDOW]
        mean = float(np.mean(window)) if window else float("nan")
        label = "final" if final else "1 min"
        print(
            f"{label}: {mean:6.3f} ms/frame over {len(window)} frames "
            f"(budget {FRAME_MS:.0f} ms), queue {self._frames.qsize()}/{self._backlog}, "
            f"processed {self._processed}, dropped {self._pump.dropped if self._pump else 0}",
            flush=True,
        )

    def _shutdown(self, capture: subprocess.Popen, playback: subprocess.Popen) -> None:
        if playback.stdin is not None:
            try:
                playback.stdin.close()
            except OSError:
                pass
        for child in (capture, playback):
            if child.poll() is None:
                child.terminate()
        for child in (capture, playback):
            try:
                child.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2.0)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Live DeepFilterNet3 denoising over PipeWire.")
    parser.add_argument("--device", default="CPU", help="OpenVINO device, e.g. CPU or NPU")
    parser.add_argument("--source", required=True, help="PipeWire source node name or id to record")
    parser.add_argument("--sink", required=True, help="PipeWire sink node name to play into")
    parser.add_argument("--models", default=str(dfn.MODELS_DIR), help="ONNX export directory")
    parser.add_argument(
        "--queue-frames",
        type=int,
        default=8,
        help="capture backlog kept in memory before frames are dropped (default 8 = 80 ms)",
    )
    args = parser.parse_args(argv)
    _require_node("sources", args.source, parser)
    _require_node("sinks", args.sink, parser)

    live = Realtime(args.device, args.source, args.sink, Path(args.models), args.queue_frames)

    def on_signal(signum: int, _frame: object) -> None:
        print(f"signal {signum}: stopping")
        live.stop()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    return live.run()


if __name__ == "__main__":
    raise SystemExit(main())
