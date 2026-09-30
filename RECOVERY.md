# Recovery Runbook — restoring from zero

Rebuild a workstation and restore all data using only Bitwarden and stock tools.
Critical-path rule: recovery uses **plain `restic` + `ssh` only** — nothing in this repo may be required to get data back.

## Inventory

- Repository: `sftp:pbackup:/mnt/backup/restic` (restic, format v2)
- Access: `ssh pbackup` — host/port/user live in `~/.ssh/config` on a live machine and in the Bitwarden item `pbackup/console`; key `~/.ssh/main` (copy attached to Bitwarden).
- The repository is also the machine-to-machine transfer medium: `backup push` on one machine, `backup pull` on the other.
- Day-to-day operations use the `backup` CLI (`dots/backup`) — see `backup/README.md` for the cheat sheet; this runbook deliberately sticks to raw `restic`.
- Snapshot tags (`source,category`): `projects,data` · `media` · `kube|talos|ssh|docker|gpg|password-store|sops-age|omp,configs`. Untagged and `manual`-tagged snapshots are never pruned by `cleanup`.
- Runtime repository password: `pass restic/backup-repo` (interactive) or the per-OS non-interactive command in `backup/config.toml` (Keychain / secret-tool) — needed for unattended scheduled runs.

## Bitwarden items to create (keep current)

| Item | Contents |
|---|---|
| `restic/backup-repo` | Repository password. Source of truth on live machines: `pass restic/backup-repo`. |
| `backup/pbackup-sftp-key` | Private key `~/.ssh/main` (attach the file). |
| `sops/age-key` | age private key (`~/.config/sops/age/keys.txt`). |
| `pbackup/console` | Out-of-band access to the backup host: provider panel / console credentials. |
| — offline, not in Bitwarden — | Bitwarden master password + 2FA recovery code (paper / second password manager). |

Why: `pass`/GPG is circular for disaster recovery — `~/.password-store` and `~/.gpg` live *inside* the repository that needs the password. Bitwarden (plus an offline copy of its own credentials) is the out-of-band copy that breaks the loop.

## Restore procedure (new machine, same OS as the snapshot)

1. Install restic: `brew install restic` (macOS) / `sudo pacman -S restic` (Arch).
2. Fetch from Bitwarden: repo password → `set -x RESTIC_PASSWORD …` (fish; do not write it to disk); key → `~/.ssh/main` (`chmod 600`); recreate the `pbackup` stanza in `~/.ssh/config`.
3. Check access: `ssh pbackup true`, then:
   ```fish
   set -x RESTIC_REPOSITORY sftp:pbackup:/mnt/backup/restic
   restic snapshots --compact
   ```
   Note the `Host` value for your machine in the listing — pin it in every restore below (`--host <value>`) so a `--target /` restore never picks the *other* OS's snapshot (paths would land under the wrong prefix).
4. Restore configuration first (small, unblocks everything else):
   ```fish
   restic restore latest --host <host> --tag sops-age --target /
   restic restore latest --host <host> --tag ssh --target /
   restic restore latest --host <host> --tag gpg --target /
   restic restore latest --host <host> --tag password-store --target /
   restic restore latest --host <host> --tag omp --target /
   restic restore latest --host <host> --tag kube --target /
   restic restore latest --host <host> --tag docker --target /
   restic restore latest --host <host> --tag talos --target /
   ```
5. Verify: `sops -d <any sops-encrypted file>` decrypts; `pass ls` works (re-import GPG keys via `gpg-import.fish` if needed); `ssh -T git@git.arsolitt.dev`.
6. Restore data:
   ```fish
   restic restore latest --host <host> --tag projects --target /
   restic restore latest --host <host> --tag media --target /
   ```
7. Integrity check: `restic check --read-data-subset=1%`.

Cross-OS restore (snapshot taken on the other OS): paths differ (`/Users/arsolitt` vs `/home/arsolitt`), so stage and copy instead of `--target /`:

```fish
restic restore latest --tag ssh --target /tmp/restore
rsync -aX /tmp/restore/<original-path-from-snapshot>/ ~/.ssh/
```

## Verification drill (do it while nothing is broken)

```fish
restic restore latest --tag ssh --target /tmp/drill --verify
diff -r /tmp/drill/<host-path>/.ssh ~/.ssh
```

Confirms the password works, the repository decrypts, and data is readable — before you actually need it. Run after any storage change and every few months.

## Known gotchas

- `pass`/GPG chain is circular by design (see above) — Bitwarden plus the offline copy is the break-glass path.
- Case sensitivity: macOS APFS is case-insensitive (verified), Linux is not. A directory containing both `Foo` and `foo` cannot be restored on macOS. Keep trees casefold-unique; a `lint` check ships with the backup tool.
- `StrictHostKeyChecking no` is set for `pbackup` — acceptable for an encrypted repo, but pinning the host key (`ssh-keyscan`) is stricter.
- Zen browser profile is *not* backed up (target commented out in `backup/config.toml`).
