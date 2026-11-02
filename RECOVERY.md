# Recovery Runbook — restoring from zero

Rebuild a workstation and restore all data using only Bitwarden and stock tools.
Critical-path rule: recovery uses **plain `restic` + `ssh` only** — nothing in this repo may be required to get data back.

## Inventory

- Repository: `sftp:pbackup:/pbackup/restic` (restic, format v2)
- Access: `ssh pbackup` — host/port/user live in `~/.ssh/config` on a live machine and in the Bitwarden item `pbackup/console`; key `~/.ssh/laptop` (copy attached to Bitwarden).
- The repository is also the machine-to-machine transfer medium: `pbackup push` on one Linux host, `pbackup pull` on another.
- Day-to-day operations use the `pbackup` CLI (`dots/pbackup`) — see `pbackup/README.md` for the cheat sheet; this runbook deliberately sticks to raw `restic`.
- Snapshot tags (`source,category`): `projects,data` · `media` · `kube|talos|ssh|docker|gpg|password-store|sops-age|omp,configs`. Untagged and `manual`-tagged snapshots are never pruned by `cleanup`.
- Runtime repository password: `pass restic/backup-repo` (interactive) or the `secret-tool` non-interactive command documented in `pbackup/config.toml` — needed for unattended scheduled runs.

## Bitwarden items to create (keep current)

| Item | Contents |
|---|---|
| `restic/backup-repo` | Repository password. Source of truth on live machines: `pass restic/backup-repo`. |
| `backup/pbackup-sftp-key` | Private key `~/.ssh/laptop` (attach the file). |
| `sops/age-key` | age private key (`~/.config/sops/age/keys.txt`). |
| `pbackup/console` | Out-of-band access to the backup host: provider panel / console credentials. |
| — offline, not in Bitwarden — | Bitwarden master password + 2FA recovery code (paper / second password manager). |

Why: `pass`/GPG is circular for disaster recovery — `~/.password-store` and `~/.gpg` live *inside* the repository that needs the password. Bitwarden (plus an offline copy of its own credentials) is the out-of-band copy that breaks the loop.

## Restore procedure (new Linux machine)

1. Install the bootstrap tools: `sudo pacman -S --needed git fish uv restic`; clone the dotfiles and run `uv run setup/install.py` (or `uv run setup/install.py --only configs` when only symlinks are needed).
2. Fetch from Bitwarden: repo password → `set -x RESTIC_PASSWORD …` (fish; do not write it to disk); key → `~/.ssh/laptop` (`chmod 600`); recreate the `pbackup` stanza in `~/.ssh/config`.
3. Check access: `ssh pbackup true`, then:
   ```fish
   set -x RESTIC_REPOSITORY sftp:pbackup:/pbackup/restic
   restic snapshots --compact
   ```
   Note your machine's hostname in the listing — pin it in every restore below (`--host <hostname>`) so a restore never picks another machine's snapshot (paths would land under the wrong prefix).
4. Restore configuration first (small, unblocks everything else):
   ```fish
   restic restore latest --host <hostname> --tag sops-age --target /
   restic restore latest --host <hostname> --tag ssh --target /
   restic restore latest --host <hostname> --tag gpg --target /
   restic restore latest --host <hostname> --tag password-store --target /
   restic restore latest --host <hostname> --tag omp --target /
   restic restore latest --host <hostname> --tag kube --target /
   restic restore latest --host <hostname> --tag docker --target /
   restic restore latest --host <hostname> --tag talos --target /
   ```
5. Verify: `sops -d <any sops-encrypted file>` decrypts; `pass ls` works (re-import GPG keys via `gpg-import.fish` if needed); `ssh -T git@git.arsolitt.dev`.
6. Restore data:
   ```fish
   restic restore latest --host <hostname> --tag projects --target /
   restic restore latest --host <hostname> --tag media --target /
   ```
7. Integrity check: `restic check --read-data-subset=1%`.

## Verification drill (do it while nothing is broken)

```fish
restic restore latest --tag ssh --target /tmp/drill --verify
diff -r /tmp/drill/home/arsolitt/.ssh ~/.ssh
```

Confirms the password works, the repository decrypts, and data is readable — before you actually need it. Run after any storage change and every few months.

## Known gotchas

- `pass`/GPG chain is circular by design (see above) — Bitwarden plus the offline copy is the break-glass path.
- `StrictHostKeyChecking no` is set for `pbackup` — acceptable for an encrypted repo, but pinning the host key (`ssh-keyscan`) is stricter.
- Zen browser profile is *not* backed up.
