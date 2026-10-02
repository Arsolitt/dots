# pbackup

Go CLI over [restic](https://restic.net/) for personal backups: snapshots of the
target registry to the SFTP repository, retention, cross-machine restore, and
scheduled runs on macOS (launchd) and Linux (systemd user timers).

> Renamed from `backup` (2026-10): binary, source dir, `PBACKUP_CONFIG` and the
> `~/.config|state|cache/pbackup` paths. Older installs: move the three old dirs
> to their pbackup names and rebuild via `install.fish`.

Disaster recovery uses plain `restic` only — see [../RECOVERY.md](../RECOVERY.md).

## Install

```fish
fish ~/dots/links.fish                               # config → ~/.config/pbackup/config.toml
go build -C ~/dots/pbackup -o ~/.local/bin/pbackup .   # or the full fish ~/dots/install.fish
```

## Daily

```fish
pbackup push                  # all targets: snapshots + retention
pbackup push ssh kube         # selected targets only
pbackup push --dry-run        # show what would happen

pbackup pull                  # restore everything (asks 'yes'; files are OVERWRITTEN)
pbackup pull projects         # one target
pbackup pull --from mac       # snapshots of a specific machine (default: newest of all)
pbackup pull --yes --verify   # no prompt, verify restored content

pbackup status                # last push/pull/prune/check + repository summary
pbackup snapshots             # this machine's snapshots (--all for every machine)
```

Switching machines: run `pbackup pull` on the other machine — the repository *is*
the transport.

## Maintenance

```fish
pbackup prune                 # show snapshots whose tags left the config registry
pbackup prune --apply         # delete them + prune + check (1% of data)
pbackup prune --host OLDNAME --apply   # one-time cleanup of a legacy host name

pbackup check --read-data-subset 5%    # integrity check
pbackup cache clean                    # drop temporary restore directories
pbackup lint                           # case/Unicode name collisions (push runs it too)
pbackup init                           # create the repository (no-op if present)
```

## Schedule

```fish
pbackup schedule render       # dry run: print launchd/systemd units
pbackup schedule install      # install both jobs (daily push, weekly prune)
pbackup schedule status       # ...or uninstall
```

Scheduled runs need a non-interactive password source (gpg-agent's cache may be
cold): use `password_command_darwin` (Keychain) or `password_command_linux`
(secret-tool) in `config.toml` — ready-made lines are in its comments.

## Layout

| Path | What |
| --- | --- |
| `dots/pbackup/config.toml` → `~/.config/pbackup/config.toml` | target registry: paths, tags, excludes, retention, schedule |
| `~/.local/state/pbackup/` | `state.json`, `log`, `schedule.log` |
| `~/.cache/pbackup/` | restic metadata cache and restore scratch |
| `internal/lint` | case/Unicode collision guard (macOS is case-insensitive) |
| `internal/schedule` | launchd / systemd unit generation |

## Notes

- Rescue snapshots: `pull` snapshots the current state first (default: `configs`
  targets; `--rescue always|never`). They are tagged `manual` — never a restore
  source, never deleted by `prune`.
- Host identity: snapshots are written as `mac` / `linux` (stable across machine
  renames). Legacy host values are not touched by `prune` (per-host scope);
  retention thins them over time.
- Retention lives in `[retention.*]` of the config and runs on every `push`
  (`--no-forget` skips it).
- Untagged snapshots are never considered stale.
