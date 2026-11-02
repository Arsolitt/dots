# npu-denoise

DeepFilterNet3 speech denoiser driven by OpenVINO, aimed at the Intel NPU so
the CPU stops paying ~35-40% of a core for microphone noise suppression.

Scripts carry their dependencies inline (PEP 723), so everything runs through
`uv run` without a project virtualenv. The tree lives in the dotfiles repo and
is linked to `~/projects/npu-denoise`; model weights are downloaded into
`~/.cache/npu-denoise/models`.

## Measured on this machine

60 s of audio, 6000 frames of 10 ms (Core Ultra 5 338H, NPU 5010):

| Path | wall | CPU time used | per frame |
|---|---|---|---|
| OpenVINO CPU | 11.7 s | 27.5 s (~46 % of one core) | 1.59 ms |
| OpenVINO NPU | 5.9 s | 4.1 s (~7 % of one core) | 0.86 ms |
| Live bridge, NPU | — | ~18 % of one core | 3.1 ms (incl. `pw-cat` I/O) |

Output of the NPU path matches the CPU path within a mean absolute sample
difference of 1.2 (16-bit scale). For reference, the LADSPA DeepFilterNet
plugin this replaces costs ~39 % of a core.

## Setup

`install.fish` in the dotfiles root installs the packages, adds the user to the
`render` group (required for `/dev/accel/accel0`) and fetches the models. The
manual equivalent:

```
sudo pacman -S uv level-zero-loader intel-npu-driver intel-npu-compiler
sudo usermod -aG render $USER      # relogin afterwards
scripts/fetch-models.sh
```

Verify:

```
uv run scripts/npu-check.py          # fast: compiles a trivial graph
uv run scripts/npu-check.py --dfn    # also compiles the DeepFilterNet graphs
```

Two things are easy to miss:

1. Without the `render` group the user-mode driver reports
   `Failed to detect any VPU device` and OpenVINO lists only `CPU`.
2. The NPU compiler only accepts static shapes. The upstream ONNX exports have
   a dynamic time axis and fail with `Got negative shape dim bound`; the host
   pins that axis to a single frame before compiling.

## How it works

`dfn.py` re-implements libDF's per-frame DSP in numpy and runs the three
upstream ONNX graphs through OpenVINO. Those graphs keep GRU state internally
in tract-pulse, which an OpenVINO graph cannot do, so each `GRUSequence` gets
its hidden state exposed as an extra graph input/output and carried in Python;
the encoder is split into conv and GRU paths because their lookahead differs.

## Virtual source

`scripts/virtual-source.sh` runs one `pw-loopback` that exposes a sink
(`npu_denoise`, where the host plays) and a source (`npu_mic`, what applications
record). A PulseAudio null-sink plus remap-source would do the same, but
pipewire-pulse splits module arguments on whitespace, so any device description
with spaces is truncated to its first word; SPA JSON passed to pw-loopback keeps
the label intact.

## Usage

Offline:

```
uv run dfn.py --in in.wav --out out.wav --device NPU
```

Live through a virtual microphone:

```
scripts/virtual-source.sh start
uv run realtime.py --device NPU \
    --source alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic1__source \
    --sink npu_denoise
# microphone "Microphone (NPU denoised)" is now available to applications
scripts/virtual-source.sh stop
```

`micns npu` in the dotfiles does the same through the user unit
`npu-denoise.service`, and points the default source at `npu_mic`. While the
unit runs it holds the microphone open, so the denoiser keeps consuming CPU
(about 18%) even with no listener; stop it with `micns off` when not in a call.

## Reference material

- Upstream project with the Python/Rust reference implementation:
  https://github.com/Rikorose/DeepFilterNet (v0.5.6)
- Intel's OpenVINO IR models: huggingface.co/Intel/deepfilternet-openvino
