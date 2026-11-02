# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "openvino>=2026.4"]
# ///
"""Live microphone denoising through PipeWire.

Two ``pw-cat`` children carry raw float32 mono 48 kHz PCM: one records the physical
source, one plays the enhanced stream into a sink (``scripts/virtual-source.sh`` turns
that sink into ``npu_mic``). A reader thread pushes captured frames into a bounded queue;
the main loop denoises and writes them to the playback child, dropping frames instead of
growing latency when playback falls behind.

Usage:
    .venv/bin/python realtime.py --source alsa_input...HiFi__Mic1__source --sink npu_denoise
"""

from __future__ import annotations

import argparse
import io
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

FRAME_BYTES = dfn.HOP_SIZE * 4
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
        "1",
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
    """Reads fixed-size capture frames and hands them to the bounded queue."""

    def __init__(
        self,
        stream: io.BufferedReader,
        frames: queue.Queue[np.ndarray],
        stop: threading.Event,
    ) -> None:
        super().__init__(name="capture", daemon=True)
        self._stream = stream
        self._frames = frames
        self._stop = stop
        self.dropped = 0

    def run(self) -> None:
        while not self._stop.is_set():
            payload = self._stream.read(FRAME_BYTES)
            if len(payload) < FRAME_BYTES:
                self._stop.set()
                return
            frame = np.frombuffer(payload, dtype=np.float32)
            try:
                self._frames.put_nowait(frame)
            except queue.Full:
                self.dropped += 1


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
                    enhanced = self._stream.process(frame)
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
