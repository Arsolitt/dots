# AGENTS.md — dots

Repo rules for agents. Overrides generic habits; facts verified 2026-11-02 against `b788495`.
Language: artifacts (code, comments, commits, docs, prompts) in English; chat with the owner in Russian.

## 1. Scope

Arch-derived Linux dotfiles (CachyOS primary) plus the installer that deploys them.
macOS support was removed in `dfbe754` — do not reintroduce it.

First-party code and config:

| Path | What it is |
|---|---|
| `setup/` | PEP 723, stdlib-only Python installer (`uv run setup/install.py`, `setup/links.py`) |
| `pbackup/` | Go backup CLI, module `github.com/Arsolitt/dots/pbackup`; user output is Russian |
| `npu-denoise/` | OpenVINO/DeepFilterNet host scripts and tests |
| `hypr/` | Hyprland Lua config (`hyprland.lua` + `conf/*.lua`), scripts, lock/idle configs |
| `fish/`, `kitty/`, `btop/`, `gtk-*`, `starship.toml`, `bin/`, `battery/`, `power-profile/`, `pipewire/`, `searxng/` | dotfiles, CLI helpers, hardware/vendor assets |
| `swappy/`, `swayimg/`, `nwg-look/`, `mimeapps.list`, `electron-flags.conf`, `gpg-*.fish`, `yay.fish` | desktop/GTK/file-association config and helper scripts |

Vendored or generated — never restyle or "fix" without an explicit ask:
`nvim/` (LazyVim starter, Apache-2.0), `kitty/current-theme.conf`, `btop/btop.conf`,
`fish/themes/kanagawa.fish`, fisher-managed functions/completions (`__git*`, `__z*`,
`_fzf_*`, `fisher`, `fzf_configure_bindings`), generated completions for
cilium/flux/kubecm/copilot/bun, `hypr/scripts/screenshot.{fish,sh}` (hyprshot fork).
Keep local edits to vendored files minimal and upstream-compatible.

## 2. Hard rule: land in the repo AND the installer, gate per device

Every patch, new feature and fix MUST exist in two places before it is done:

1. the repo artifact — config, script, step, package entry;
2. the installer path that reproduces it on a fresh host.

A change reachable only through manual `cp`, `ln` or one-off commands is incomplete.
Equally, never add installer behavior whose artifact is not in this repo. Commands you
run on the live host are drafts: turn them into a repo script plus an installer step, then
re-run through the installer to prove a fresh host gets the same result.

Anything platform- or device-specific MUST be gated to the devices it applies to.
Unconditional is allowed only for behavior that is correct and harmless on every
Arch-derived host (fish, git, kitty, starship, base packages). Hardware, firmware and
vendor quirks are never unconditional. OS and chassis differences follow the same rule:
this repo targets Arch-derived Linux only, and the DMI chassis type is the only host
split — do not add macOS or Windows branches.

Self-check before reporting done: `uv run setup/install.py --list` shows the new step or
gate, `--dry-run` performs no writes, and a host without the feature skips the step with
a `requires <feature>` reason.

| Change | Installer registration |
|---|---|
| Linked config dir/file | add to `CONFIG_DIRS` / `LINUX_DIRS` / `LINUX_FILES` / `BIN_FILES` or an explicit `Link(...)` in `setup/dotfiles/steps/s20_configs.py`; per-host alternative is `[[links.extra]]` in a device profile |
| Package | `BASE_PACKAGES` / `DESKTOP_PACKAGES` / feature tuple in `s10_pacman.py`, or `AUR_PACKAGES` in `s11_aur.py`; per-host `[packages].extra` |
| System action (unit, PAM, sudo script, service) | new `setup/dotfiles/steps/sNN_topic.py` exporting `STEP`; discovery is automatic by filename |
| Hardware behavior | probe in `setup/dotfiles/detect.py`, key added to `detect.device().detected`, `requires=(...)` on the step, pin in `setup/devices/<hostname>.toml` |
| New host-only Hyprland config | module selected in `hypr/hyprland.lua` (laptop vs desktop), never a shared `conf/*.lua` |

Do not ship a fix that only works on the current machine. If a check cannot be detected
automatically, add a profile-only feature (like `platform_profile_fix`) and document it
in `setup/devices/example.toml` so the gate is explicit and reproducible.

## 3. Device gating model

Resolution order: hardware probe → device profile → `--profile` / `DOTS_PROFILE` overlay.
Feature values are `auto` (use detection), `on` (force) or `off` (disable).
`on` bypasses detection, so prefer `auto` plus a host pin.

Current features (`setup/devices/example.toml`):

| Feature | Detector | Consumer |
|---|---|---|
| `fingerprint` | allow-listed USB `idVendor` | `s52_fingerprint` (rewrites PAM) |
| `charge_limit` | battery + `XIAOMI` / `REDMI BOOK` DMI strings | `s51_battery` (WMI `WMAA`, 80% cap) |
| `npu` | `/sys/class/accel/accel0` driven by `intel_vpu` | `s50_npu`, NPU links in `s20_configs` |
| `docker` | `shutil.which("docker")` | `s41_searxng` only — the `docker` step has no gate and always runs |
| `battery` | `BAT*` power supply | nothing yet; do not assume it gates charge limits |
| `platform_profile_fix` | none — profile-only | `s53_power_profile` (Xiaomi ppd quirk) |

Hyprland cannot read installer features, so it switches on DMI chassis type itself:
`hypr/hyprland.lua` loads `conf/laptop.lua` for `{8,9,10,14}`, else `conf/desktop.lua`
(fallback is desktop). Keep `detect.LAPTOP_CHASSIS` and this Lua check in sync.
Monitor modes, scales, workspace counts, lid behavior and pointer devices belong in
those two modules; shared modules stay host-agnostic.

## 4. Installer contract

- Run only through `uv`: `uv run setup/install.py` (all steps) or `uv run setup/links.py`
  (only the `configs` step; `--cleanup` removes broken repo links).
- `install.py` flags: `--list`, `--dry-run`, `--only NAME`, `--skip NAME`, `--profile PATH`,
  `--no-backup`. `links.py` has `--dry-run`, `--no-backup`, `--cleanup`, `--profile`.
- Steps: one concern per `sNN_topic.py`, filename order is execution order, module exports
  one `STEP = Step(name, title, requires, run)`. `name` is what `--only`/`--skip` take.
- Mutations go through `ctx.run(...)` (dry-run aware); probes use `ctx.read()` (always runs)
  or `ctx.ok()` (quiet boolean). Every step must be idempotent: probe state, skip when done.
- `s20_configs.py` is the single source of truth for symlinks. Everything this step
  installs is a symlink, never a copy; collisions are renamed to
  `<name>.backup-YYYYmmdd-HHMMSS` unless `--no-backup`. Linking a directory replaces a
  pre-existing real directory wholesale. Cleanup only removes broken links targeting this repo.
- Keep the installer stdlib-only; changing the PEP 723 `dependencies` header is a
  deliberate decision, not a convenience.
- Exit codes: `2` unsupported host or invalid profile, `1` collected step errors, `0` clean.

## 5. Hyprland

- Config is Lua only (`hyprland.lua`); old hyprlang INI files survive only in git history as
  rollback, not as a second config surface.
- `require` order matters: `variables.lua` and host modules run before consumers such as
  `windowrules.lua` (`PRIMARY_MONITOR`) and `keyboard.lua`.
- Fetch https://wiki.hypr.land/Configuring/ only for Hyprland topics; do not fetch it for
  waybar, noctalia, rofi, fuzzel, etc. The installed Lua API stubs live in
  `/usr/share/hypr/stubs/hl.meta.lua`.
- Use the documentation as the sole source for fields and functions. If it does not
  mention something, say "Documentation does not mention" — never invent fields.
- Answer with Lua and comment non-obvious choices.

## 6. Conventions

- No comment noise: comments state non-obvious why, invariants or traps. No dead code,
  no commented-out alternatives without a reason.
- Conventional Commits with `--signoff`; GPG-signed; no AI attribution. English subjects.
- Never commit secrets: use `secret-tool` / `pass`; commit templates with placeholders and
  generate values at install time (see `searxng/settings.yml.template`).
- Machine-local state stays untracked: `fish/fish_variables`, `tmux/plugins/`,
  `__pycache__/`, `*.pyc`. Do not commit generated bytecode.
- Host profiles are tracked (`setup/devices/<hostname>.toml`); local overrides go through
  `--profile` or `DOTS_PROFILE` and stay out of the repo.
- When touching shared config, do not add host assumptions (output names, ALSA device
  names, user paths). Move them into a host module or a gated artifact.

## 7. Verification

No CI exists; run the relevant checks yourself before reporting done.

| Area | Command |
|---|---|
| Installer tests | `cd setup && uv run python -m unittest discover -s tests` (29 tests) |
| Gate/plan proof | `uv run setup/install.py --list` |
| Installer dry-run | `uv run setup/install.py --dry-run` |
| Link-only dry-run | `uv run setup/links.py --dry-run` |
| Lua syntax | `luac -p hypr/hyprland.lua hypr/conf/*.lua` |
| Fish syntax | `fish --no-execute fish/config.fish fish/conf.d/*.fish fish/functions/*.fish fish/completions/*.fish` |
| Live Hyprland | `hyprctl reload && hyprctl configerrors` |
| Go | `go test -C pbackup ./...`, `go vet -C pbackup ./...`, `gofmt -l pbackup` |

Known state: `TestIntegrationUnlockStaleLock` in `pbackup` fails deterministically on this
host (restic finishes before a complete lock file is observed) — not a dotfiles regression.
Verifying a gate means showing it in `--list` output, not reading the code only.

## 8. Known debt — do not extend

- `README.md` component list is stale (hyprpaper/waybar/rofi/swappy; the actual stack is
  noctalia + satty). Do not copy it into new docs.
- Stale references to removed `install.fish` / `links.fish` remain in `npu-denoise/README.md`,
  `pbackup/pull.go`, `fish/functions/micns.fish`; `fish/conf.d/machine-paths.fish` still
  claims the universal store is committed (it is ignored).
- Host assumptions leak into shared files: `DP-2` in `hypr/conf/keyboard.lua`,
  fingerprint in `hypr/hyprlock.conf`, `SSH_ASKPASS` in `hypr/conf/environment.lua`,
  `/home/arsolitt` in `pipewire/*.conf`, a hardcoded ALSA source in
  `systemd/user/npu-denoise.service`. Fix or gate these when touched; never add more.
- `s53_power_profile` and its script have no vendor re-check; the gate is the profile only.
