#!/usr/bin/env bash
#
# Dotfiles installer. Symlinks configs into $HOME, skipping
# Linux-only configs when running on macOS.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
DRY_RUN=0
BACKUP=1

if [[ -t 1 ]]; then
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_GREEN="" C_YELLOW="" C_BLUE="" C_RED="" C_DIM="" C_RESET=""
fi

log_info() { printf "%s==>%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
log_ok()   { printf "%s +%s  %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
log_skip() { printf "%s .%s  %s%s%s\n" "$C_DIM" "$C_RESET" "$C_DIM" "$*" "$C_RESET"; }
log_warn() { printf "%s !%s  %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
log_err()  { printf "%s x%s  %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }

usage() {
    cat <<EOF
Usage: ${0##*/} [--dry-run] [--no-backup] [--help]

Symlinks dotfiles into \$HOME. Skips Linux-only configs on macOS.

Options:
  --dry-run     Print what would be done without making changes.
  --no-backup   Overwrite existing files/links instead of backing them up.
  --help        Show this message.

Detected:
  OS            $OS
  Dotfiles dir  $DOTFILES_DIR
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=1 ;;
        --no-backup) BACKUP=0 ;;
        --help|-h)   usage; exit 0 ;;
        *)           log_err "unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0
    if (( DRY_RUN )); then
        log_info "would create dir $dir"
    else
        mkdir -p "$dir"
        log_ok "created dir $dir"
    fi
}

link() {
    local src="$1" dst="$2"

    if [[ ! -e "$src" ]]; then
        log_warn "source missing, skip: $src"
        return 0
    fi

    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        log_skip "already linked: $dst"
        return 0
    fi

    if [[ -e "$dst" || -L "$dst" ]]; then
        if (( BACKUP )); then
            local backup="$dst.backup-$(date +%Y%m%d-%H%M%S)"
            if (( DRY_RUN )); then
                log_info "would backup $dst -> $backup"
            else
                mv "$dst" "$backup"
                log_warn "backed up $dst -> $backup"
            fi
        else
            if (( DRY_RUN )); then
                log_info "would remove existing $dst"
            else
                rm -rf "$dst"
            fi
        fi
    fi

    if (( DRY_RUN )); then
        log_info "would link $src -> $dst"
    else
        ln -s "$src" "$dst"
        log_ok "linked $dst"
    fi
}

COMMON_CONFIGS=(
    fish
    git
    kitty
    btop
)

LINUX_CONFIGS=(
    hypr
    rofi
    waybar
    swaync
    swappy
    swayimg
    nwg-look
    gtk-2.0
    gtk-3.0
    gtk-4.0
)

LINUX_FILES=(
    mimeapps.list
    electron-flags.conf
)

install_common() {
    log_info "installing common configs"
    local name
    for name in "${COMMON_CONFIGS[@]}"; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
}

install_linux() {
    if [[ "$OS" != "Linux" ]]; then
        log_skip "skipping Linux-only configs (OS: $OS)"
        return 0
    fi

    log_info "installing Linux-only configs"
    local name
    for name in "${LINUX_CONFIGS[@]}"; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
    for name in "${LINUX_FILES[@]}"; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
}

install_syncthing() {
    log_info "installing Syncthing .stignore files"

    local -A STIGNORE_MAP=(
        [projects]="$HOME/projects"
        [claude]="$HOME/.claude"
        [opencode]="$HOME/.config/opencode"
        [pictures]="$HOME/Pictures"
    )

    local name dest
    for name in "${!STIGNORE_MAP[@]}"; do
        dest="${STIGNORE_MAP[$name]}"
        ensure_dir "$dest"
        link "$DOTFILES_DIR/syncthing/${name}.stignore" "$dest/.stignore"
    done
}

install_gpg() {
    log_info "installing gpg-agent config"
    ensure_dir "$HOME/.gnupg"

    local src="$DOTFILES_DIR/gpg-agent.conf"
    if [[ "$OS" == "Darwin" ]]; then
        src="$DOTFILES_DIR/gpg-agent.macos.conf"
        log_warn "macOS: ensure pinentry-mac is installed (brew install pinentry-mac)"
    fi
    link "$src" "$HOME/.gnupg/gpg-agent.conf"
}

main() {
    log_info "OS: $OS"
    log_info "dotfiles: $DOTFILES_DIR"
    (( DRY_RUN ))  && log_info "dry-run mode — no changes will be applied"
    (( ! BACKUP )) && log_warn "backup disabled — existing files will be overwritten"

    ensure_dir "$HOME/.config"
    install_common
    install_linux
    install_gpg
    install_syncthing

    log_ok "done"
}

main "$@"
