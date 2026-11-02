# setup — Python dotfiles installer

`install.py` and `links.py` are PEP 723 scripts run by `uv`; they need no
virtualenv, `pyproject.toml`, or third-party packages.

```fish
uv run setup/install.py --list
uv run setup/install.py --dry-run
uv run setup/install.py
```

## Flow

```
install.py
  detect.check_host()        Linux + Arch-derived, else exit 2
  detect.device()            hostname, chassis, detected features
  profile.load()             setup/devices/<hostname>.toml + --profile overlay
  profile.resolve()          auto | on | off -> bool
  steps.discover()           import sNN_*.py in filename order
  steps.plan()               run / skip + reason for every step
  step.run(ctx)              one concern per module, failures collected
```

`links.py` is the same flow with one step (`configs`) and `--cleanup`.

## Modules

| Path | Responsibility |
|---|---|
| `dotfiles/cli.py` | `Context`: logging, `run`/`capture`/`ok`/`read`, sudo, dry-run, error list |
| `dotfiles/detect.py` | distro/chassis parsers and hardware probes |
| `dotfiles/profile.py` | TOML device profiles, feature overrides, extra packages/links |
| `dotfiles/packages.py` | pacman and AUR probe/install helpers |
| `dotfiles/links.py` | link reconciliation, timestamped backups, broken-link cleanup |
| `dotfiles/steps/__init__.py` | `Step`, discovery, plan resolution |
| `dotfiles/steps/sNN_*.py` | one setup concern per file |

## Step contract

A step module exports one value:

```python
STEP = Step(name="npu", title="...", requires=("npu",), run=_run)
```

`requires` names resolved features; a false feature prints a skip instead of
running. `run(ctx)` uses `ctx.run()` for mutations and `ctx.read()` for
read-only probes. `Context.run` prints `would run: ...` and returns without
executing in dry-run; `Context.read` is always safe to execute.

## Adding a device

Create `setup/devices/<hostname>.toml` (copy `example.toml`). Features accept
`auto`, `on`, or `off`; `[packages].extra` appends pacman packages and
`[[links.extra]]` appends symlinks. Use `--profile PATH` or `DOTS_PROFILE` for
a machine-local overlay that is not committed.

## Adding a step

Add `dotfiles/steps/sNN_name.py` exporting `STEP`. Discovery is automatic and
ordered by filename; no registry edit is needed. Declare `requires` for a
gated step and keep mutations inside `Context.run`.
