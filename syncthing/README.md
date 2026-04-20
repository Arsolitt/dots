# Syncthing Setup Guide

Post-installation setup for syncing dotfiles, projects, and personal files across Linux and macOS devices.

## Installation

### Linux (Arch / CachyOS)

```bash
sudo pacman --sync --needed syncthing
systemctl --user enable --now syncthing.service
```

### macOS

```bash
brew install syncthing
brew services start syncthing
```

## Initial Configuration

Syncthing Web UI opens at `http://127.0.0.1:8384`.

1. Open the Web UI on the new device
2. Go to **Actions → Settings → General** and set a device name
3. Note the **Device ID** (Actions → Show ID) — you'll need it to pair devices

## Install Dotfiles

Run the dotfiles installer to symlink `.stignore` files:

```bash
cd ~/.config/dots
bash links.sh
```

This creates the following symlinks in each synced folder:

| Folder | Symlinks created |
| --- | --- |
| `~/projects/` | `.stignore`, `.stignore.default`, `.stignore.dev` |
| `~/Pictures/` | `.stignore`, `.stignore.default` |
| `~/.claude/` | `.stignore`, `.stignore.default` |
| `~/.config/opencode/` | `.stignore`, `.stignore.default` |

## Add Remote Devices

On each existing device:

1. Go to **Add Remote Device**
2. Paste the new device's **Device ID**
3. Set a name and confirm
4. Accept the pairing request on the new device

## Add Shared Folders

Add folders in the Web UI or edit `config.xml` directly.

### Recommended folder configuration

| Folder Label | Path | Folder Type | Ignore Patterns |
| --- | --- | --- | --- |
| Projects | `~/projects` | Send & Receive | dev (build artifacts, deps, archives) |
| Pictures | `~/Pictures` | Send & Receive | default (OS junk, editor temps) |
| Claude Config | `~/.claude` | Send & Receive | default + claude-specific |
| OpenCode Config | `~/.config/opencode` | Send & Receive | default + opencode-specific |

When adding a folder:

1. Click **Add Folder**
2. Set **Folder Label** and **Folder Path**
3. Under **Sharing** tab, select which devices to share with
4. Under **File Versioning**, configure if needed (Simple, recommended for documents)
5. Under **Ignore Patterns**, verify that `.stignore` is detected (shown in the UI)
6. Save

## Ignore Patterns Architecture

```text
.stignore.default (universal safe patterns)
├── OS-generated files (macOS, Windows, Linux)
├── Sync tool artifacts (Syncthing, Resilio, iCloud)
├── Editor temp files (Vim, Emacs, LibreOffice, MS Office)
├── Version control (.git, .svn, .hg)
└── Thumbnails and caches

.stignore.dev (extends default — for development folders)
├── IDE project files (.idea, .vscode, .fleet)
├── Build artifacts (build/, dist/, compiled objects)
├── Language dependencies (node_modules, vendor, target, venv, .gradle)
├── Infrastructure state (.terraform, .tfstate)
├── Testing and coverage output
├── AI/LLM tool state (.claude, .codex)
├── Logs, PIDs, runtime files
└── Archives (.zip, .tar, .gz, .iso)
```

Include chain:

```text
~/projects/.stignore
  └── #include .stignore.dev
        └── #include .stignore.default

~/Pictures/.stignore
  └── #include .stignore.default
```

All `#include` paths are relative to the folder root — no absolute paths, works on both Linux and macOS.

## Adding a New Synced Folder

1. Create a new `.stignore` file in `~/.config/dots/syncthing/`:

   ```bash
   # For a non-dev folder (documents, media, configs):
   echo '#include .stignore.default' > ~/.config/dots/syncthing/newfolder.stignore

   # For a dev folder (code, projects):
   echo '#include .stignore.dev' > ~/.config/dots/syncthing/newfolder.stignore
   ```

   Add folder-specific patterns below the `#include` line if needed.

2. Register the folder in `links.sh` — add to `STIGNORE_MAP`:

   ```bash
   local -A STIGNORE_MAP=(
       [projects]="$HOME/projects"
       [claude]="$HOME/.claude"
       [opencode]="$HOME/.config/opencode"
       [pictures]="$HOME/Pictures"
       [newfolder]="$HOME/newfolder"  # ← add this
   )
   ```

   If it's a dev folder, also add to `DEV_FOLDERS`:

   ```bash
   local -a DEV_FOLDERS=(projects newfolder)
   ```

3. Re-run the installer:

   ```bash
   bash ~/.config/dots/links.sh
   ```

4. Add the folder in Syncthing Web UI on all devices.

## Useful Commands

```bash
# Check Syncthing status (Linux)
systemctl --user status syncthing.service

# View logs (Linux)
journalctl --user --unit syncthing.service --follow

# Check Syncthing status (macOS)
brew services info syncthing

# Restart Syncthing (Linux)
systemctl --user restart syncthing.service

# Restart Syncthing (macOS)
brew services restart syncthing
```

## Troubleshooting

### Missing include file causes high CPU / memory

If `.stignore` references a file that doesn't exist (e.g., `.stignore.default` symlink is broken), Syncthing may spin and consume excessive resources. Fix: re-run `links.sh` to recreate symlinks.

### Patterns not applied after editing

Syncthing rescans patterns periodically. Force rescan: click **Rescan** on the folder in the Web UI, or restart Syncthing.

### Conflict files appearing

Files matching `*sync-conflict-*` are already ignored by `default.stignore`. If old conflict files exist, delete them manually — ignore patterns only prevent future syncing.
