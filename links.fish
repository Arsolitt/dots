#!/usr/bin/env fish
#
# Dotfiles installer. Symlinks configs into $HOME, skipping
# Linux-only configs when running on macOS.

set -g DOTFILES_DIR (realpath (path dirname (status filename)))
set -g OS (uname -s)
set -g DRY_RUN 0
set -g BACKUP 1
set -g _CLEANUP_ONLY 0

# --- Color helpers (noop when not a tty) ---

function _use_color
    isatty stdout
end

function log_info
    if _use_color
        set_color blue
        printf '==>'
        set_color normal
    else
        printf '==>'
    end
    printf ' %s\n' "$argv"
end

function log_ok
    if _use_color
        set_color green
        printf ' +'
        set_color normal
    else
        printf ' +'
    end
    printf '  %s\n' "$argv"
end

function log_skip
    if _use_color
        set_color brblack
        printf ' .'
        set_color normal
        printf '  '
        set_color brblack
        printf '%s' "$argv"
        set_color normal
        printf '\n'
    else
        printf ' .  %s\n' "$argv"
    end
end

function log_warn
    if _use_color
        set_color yellow
        printf ' !'
        set_color normal
    else
        printf ' !'
    end
    printf '  %s\n' "$argv"
end

function log_err
    if _use_color
        set_color red
        printf ' x'
        set_color normal
    else
        printf ' x'
    end
    printf '  %s\n' "$argv" >&2
end

# --- Usage ---

function usage
    set -l script (status filename)
    printf 'Usage: %s [--dry-run] [--no-backup] [--cleanup] [--help]\n' (path basename $script)
    printf '\n'
    printf 'Symlinks dotfiles into $HOME. Skips Linux-only configs on macOS.\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --dry-run     Print what would be done without making changes.\n'
    printf '  --no-backup   Overwrite existing files/links instead of backing them up.\n'
    printf '  --cleanup     Remove broken dotfiles symlinks, then exit (skip install).\n'
    printf '  --help        Show this message.\n'
    printf '\n'
    printf 'Detected:\n'
    printf '  OS            %s\n' $OS
    printf '  Dotfiles dir  %s\n' $DOTFILES_DIR
end

# --- Argument parsing ---

argparse --name=links 'h/help' 'dry-run' 'no-backup' 'c/cleanup' -- $argv
or begin
    usage >&2
    exit 2
end

if set --query _flag_help
    usage
    exit 0
end
set --query _flag_dry_run; and set DRY_RUN 1
set --query _flag_no_backup; and set BACKUP 0
set --query _flag_cleanup; and set _CLEANUP_ONLY 1

if test (count $argv) -gt 0
    log_err "unknown argument: $argv[1]"
    usage >&2
    exit 2
end

# --- Helpers ---

function ensure_dir --argument-names dir
    test -d "$dir"; and return 0
    if test $DRY_RUN -eq 1
        log_info "would create dir $dir"
    else
        mkdir -p "$dir"
        log_ok "created dir $dir"
    end
end

function link --argument-names src dst
    if not test -e "$src"
        log_warn "source missing, skip: $src"
        return 0
    end

    set -l real_src (realpath "$src")
    if test "$real_src" = (realpath (path dirname "$dst"))/(path basename "$dst")
        log_warn "source equals destination, skip: $dst"
        return 0
    end

    if test -L "$dst"; and test (readlink "$dst") = "$src"
        log_skip "already linked: $dst"
        return 0
    end

    if test -e "$dst"; or test -L "$dst"
        if test $BACKUP -eq 1
            set -l backup "$dst.backup-"(date +%Y%m%d-%H%M%S)
            if test $DRY_RUN -eq 1
                log_info "would backup $dst -> $backup"
            else
                mv "$dst" "$backup"
                log_warn "backed up $dst -> $backup"
            end
        else
            if test $DRY_RUN -eq 1
                log_info "would remove existing $dst"
            else
                rm -rf "$dst"
            end
        end
    end

    if test $DRY_RUN -eq 1
        log_info "would link $src -> $dst"
    else
        ln -s "$src" "$dst"
        log_ok "linked $dst"
    end
end

# Checks if a symlink is broken AND points into $DOTFILES_DIR.
# Returns 0 (removed) or 1 (skipped — not ours, or still working).
function _try_remove_link --argument-names linkpath
    set -l target (readlink "$linkpath")
    # Only touch symlinks that point into our dotfiles tree.
    string match -q "$DOTFILES_DIR/*" -- $target; or return 1
    # Still resolves? Leave it alone.
    test -e "$linkpath"; and return 1
    if test $DRY_RUN -eq 1
        log_info "would remove broken link: $linkpath"
    else
        rm "$linkpath"
        log_warn "removed broken link: $linkpath"
    end
    return 0
end

# --- Config lists ---

set -g COMMON_CONFIGS \
    fish \
    git \
    kitty \
    btop

set -g LINUX_CONFIGS \
    hypr \
    rofi \
    waybar \
    swaync \
    swappy \
    swayimg \
    nwg-look \
    gtk-2.0 \
    gtk-3.0 \
    gtk-4.0

set -g LINUX_FILES \
    mimeapps.list \
    electron-flags.conf

set -g MACOS_CONFIGS \
    rift

# --- Installers ---

function install_common
    log_info "installing common configs"
    for name in $COMMON_CONFIGS
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    end
    # starship prompt config — top-level file in .config
    link "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"
end

function install_linux
    if test "$OS" != Linux
        log_skip "skipping Linux-only configs (OS: $OS)"
        return 0
    end

    log_info "installing Linux-only configs"
    for name in $LINUX_CONFIGS
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    end
    for name in $LINUX_FILES
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    end
end

function install_macos
    if test "$OS" != Darwin
        log_skip "skipping macOS-only configs (OS: $OS)"
        return 0
    end

    log_info "installing macOS-only configs"
    for name in $MACOS_CONFIGS
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    end
end

function install_gpg
    log_info "installing gpg-agent config"
    ensure_dir "$HOME/.gnupg"

    set -l src "$DOTFILES_DIR/gpg-agent.conf"
    if test "$OS" = Darwin
        set src "$DOTFILES_DIR/gpg-agent.macos.conf"
        log_warn "macOS: ensure pinentry-mac is installed (brew install pinentry-mac)"
    end
    link "$src" "$HOME/.gnupg/gpg-agent.conf"
end

# --- Main ---

# Walks the install locations and removes symlinks that point into the
# dotfiles tree but no longer resolve (e.g. after renaming/deleting a config).
function cleanup_broken_links
    log_info "scanning for broken dotfiles symlinks"

    # Directories where installers create symlinks (add new locations here).
    set -l scan_dirs "$HOME/.config" "$HOME/.gnupg"
    for extra in "$HOME/projects" "$HOME/.claude" "$HOME/Pictures"
        test -d "$extra"; and set -a scan_dirs "$extra"
    end

    set -l count 0
    # Recursive scan of config dirs + syncthing target locations
    for dir in $scan_dirs
        test -d "$dir"; or continue
        for linkpath in (find "$dir" -type l -print0 | string split0)
            _try_remove_link "$linkpath"; and set count (math $count + 1)
        end
    end
    # Shallow scan: $HOME top-level files (e.g. mimeapps.list, electron-flags.conf)
    for linkpath in (find "$HOME" -maxdepth 1 -type l -print0 | string split0)
        _try_remove_link "$linkpath"; and set count (math $count + 1)
    end

    test $count -eq 0; and log_skip "no broken dotfiles symlinks found"
    test $count -gt 0; and log_ok "cleaned up $count broken link(s)"
end

log_info "OS: $OS"
log_info "dotfiles: $DOTFILES_DIR"
test $DRY_RUN -eq 1; and log_info "dry-run mode — no changes will be applied"
test $BACKUP -eq 0; and log_warn "backup disabled — existing files will be overwritten"
test $_CLEANUP_ONLY -eq 1; and log_info "cleanup-only mode — skipping install"

ensure_dir "$HOME/.config"
cleanup_broken_links

if test $_CLEANUP_ONLY -eq 0
    install_common
    install_linux
    install_macos
    install_gpg
end

test $_CLEANUP_ONLY -eq 0; and log_ok done

# --- Cleanup globals so sourcing doesn't pollute the shell ---

set --erase DOTFILES_DIR OS DRY_RUN BACKUP _CLEANUP_ONLY
set --erase COMMON_CONFIGS LINUX_CONFIGS LINUX_FILES MACOS_CONFIGS
functions --erase _use_color log_info log_ok log_skip log_warn log_err usage
functions --erase ensure_dir link _try_remove_link
functions --erase install_common install_linux install_macos install_gpg cleanup_broken_links
