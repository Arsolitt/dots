#!/usr/bin/env fish
#
# Dotfiles installer. Symlinks configs into $HOME, skipping
# Linux-only configs when running on macOS.

set -g DOTFILES_DIR (realpath (path dirname (status filename)))
set -g OS (uname -s)
set -g DRY_RUN 0
set -g BACKUP 1

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
    printf 'Usage: %s [--dry-run] [--no-backup] [--help]\n' (path basename $script)
    printf '\n'
    printf 'Symlinks dotfiles into $HOME. Skips Linux-only configs on macOS.\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --dry-run     Print what would be done without making changes.\n'
    printf '  --no-backup   Overwrite existing files/links instead of backing them up.\n'
    printf '  --help        Show this message.\n'
    printf '\n'
    printf 'Detected:\n'
    printf '  OS            %s\n' $OS
    printf '  Dotfiles dir  %s\n' $DOTFILES_DIR
end

# --- Argument parsing ---

argparse --name=links 'h/help' 'dry-run' 'no-backup' -- $argv
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

# --- Installers ---

function install_common
    log_info "installing common configs"
    for name in $COMMON_CONFIGS
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    end
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

function install_syncthing
    log_info "installing Syncthing .stignore files"

    set -l ST_NAMES projects claude opencode pictures
    set -l ST_DESTS \
        "$HOME/projects" \
        "$HOME/.claude" \
        "$HOME/.config/opencode" \
        "$HOME/Pictures"
    set -l DEV_FOLDERS projects

    for i in (seq (count $ST_NAMES))
        set -l name $ST_NAMES[$i]
        set -l dest $ST_DESTS[$i]
        ensure_dir "$dest"
        link "$DOTFILES_DIR/syncthing/default.stignore" "$dest/.stignore.default"
        link "$DOTFILES_DIR/syncthing/$name.stignore" "$dest/.stignore"
    end

    for dev in $DEV_FOLDERS
        for i in (seq (count $ST_NAMES))
            if test "$ST_NAMES[$i]" = "$dev"
                link "$DOTFILES_DIR/syncthing/dev.stignore" "$ST_DESTS[$i]/.stignore.dev"
                break
            end
        end
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

log_info "OS: $OS"
log_info "dotfiles: $DOTFILES_DIR"
test $DRY_RUN -eq 1; and log_info "dry-run mode — no changes will be applied"
test $BACKUP -eq 0; and log_warn "backup disabled — existing files will be overwritten"

ensure_dir "$HOME/.config"
install_common
install_linux
install_gpg
install_syncthing

log_ok done

# --- Cleanup globals so sourcing doesn't pollute the shell ---

set --erase DOTFILES_DIR OS DRY_RUN BACKUP
set --erase COMMON_CONFIGS LINUX_CONFIGS LINUX_FILES
functions --erase _use_color log_info log_ok log_skip log_warn log_err usage
functions --erase ensure_dir link
functions --erase install_common install_linux install_syncthing install_gpg
