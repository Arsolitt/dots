<h1 align="center">dots</h1>

## Install

Prerequisites on Arch Linux (CachyOS included):

```fish
sudo pacman -S --needed git fish uv
```

Preview the resolved step plan, dry-run it, then install:

```fish
uv run setup/install.py --list
uv run setup/install.py --dry-run
uv run setup/install.py
```

## Device gates

`setup/install.py --list` prints the detected host, resolved features and the
per-step plan. Hardware steps stay off where the hardware is absent:
fingerprint PAM wiring needs a USB sensor, the 80% cap needs a Xiaomi WMI
battery, the NPU denoiser needs `/sys/class/accel/accel0`, and SearXNG needs
docker. Hyprland keeps its own laptop/desktop selection from the DMI chassis
type at runtime.

Per-host overrides live in `setup/devices/<hostname>.toml`; `--profile PATH`
(or `DOTS_PROFILE`) overlays a machine-local file on top. Feature values are
`auto` (detected), `on` or `off`; `[packages].extra` adds packages and
`[[links.extra]]` adds symlinks without editing code. See
[`setup/README.md`](setup/README.md) for the module and step contract.

## Linux (CachyOS + Hyprland)
- Hyprland
- Hyprpaper
- Hyprlock
- Waybar
- Rofi
- Nemo
- Kitty
- Kitty theme: Kanagawa
- Fish
- Starship prompt (Kanagawa two-line)
- Fish theme: Kanagawa
- Screenshots: Grim + Slurp + Swappy
- Cursor: vimix Kanagawa Lotus
- GTK: Kanagawa Orange Dark
- Icons: Kanagawa
- Font: FantasqueSansM
- Microphone noise suppression: `micns` — PipeWire filter-chain presets (RNNoise, DeepFilterNet LADSPA) or the NPU denoiser (`micns npu`, ~7% of a core; host in `npu-denoise/`, models in `~/.cache/npu-denoise`)
- Battery charge cap: `battery/charge-limit.sh` — firmware 80% limit via WMI `WMAA`, systemd unit on boot plus udev rule on AC plug
- Power profiles: `power-profile/ppd-platform-driver.sh install` — keeps power-profiles-daemon off the ACPI `platform_profile` path that Xiaomi firmware closes on USB-C power
- Docker + docker compose (docker group for rootless CLI access)
- SearXNG (docker compose, loopback 127.0.0.1:8080, JSON API)

## Screenshots

![image](README/screen_1.png)

## Wallpapers

#### Original
![image](README/blackhole-anime.jpeg)
