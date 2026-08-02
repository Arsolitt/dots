#!/usr/bin/env zsh
#
# Dotfiles installer. Symlinks configs into $HOME, skipping
# Linux-only configs when running on macOS.

emulate -L zsh

DOTFILES_DIR="${0:A:h}"
OS="$(uname -s)"
DRY_RUN=0
BACKUP=1
_CLEANUP_ONLY=0
# --- Color helpers (noop when not a tty) ---

_use_color() {
    [[ -t 1 ]]
}

log_info() {
    if _use_color; then
        printf '\033[34m==>\033[0m %s\n' "$*"
    else
        printf '==> %s\n' "$*"
    fi
}

log_ok() {
    if _use_color; then
        printf ' \033[32m+\033[0m  %s\n' "$*"
    else
        printf ' +  %s\n' "$*"
    fi
}

log_skip() {
    if _use_color; then
        printf ' \033[90m.\033[0m  \033[90m%s\033[0m\n' "$*"
    else
        printf ' .  %s\n' "$*"
    fi
}

log_warn() {
    if _use_color; then
        printf ' \033[33m!\033[0m  %s\n' "$*"
    else
        printf ' !  %s\n' "$*"
    fi
}

log_err() {
    if _use_color; then
        printf ' \033[31mx\033[0m  %s\n' "$*" >&2
    else
        printf ' x  %s\n' "$*" >&2
    fi
}

# --- Usage ---

usage() {
    local script="$0"
    printf 'Usage: %s [--dry-run] [--no-backup] [--cleanup] [--help]\n' "${script:t}"
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
    printf '  OS            %s\n' "$OS"
    printf '  Dotfiles dir  %s\n' "$DOTFILES_DIR"
}

# --- Argument parsing ---

_help=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    _help=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --no-backup)  BACKUP=0; shift ;;
        --cleanup)    _CLEANUP_ONLY=1; shift ;;
        --)           shift; break ;;
        -*)           log_err "unknown option: $1"; usage >&2; exit 2 ;;
        *)            break ;;
    esac
done

if [[ $_help -eq 1 ]]; then
    usage
    exit 0
fi

if [[ $# -gt 0 ]]; then
    log_err "unknown argument: $1"
    usage >&2
    exit 2
fi

# --- Helpers ---

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0
    if [[ $DRY_RUN -eq 1 ]]; then
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

    local real_src
    real_src="$(realpath "$src")"
    if [[ "$real_src" == "$(realpath "${dst:h}")/${dst:t}" ]]; then
        log_warn "source equals destination, skip: $dst"
        return 0
    fi

    if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
        log_skip "already linked: $dst"
        return 0
    fi

    if [[ -e "$dst" ]] || [[ -L "$dst" ]]; then
        if [[ $BACKUP -eq 1 ]]; then
            local backup="$dst.backup-$(date +%Y%m%d-%H%M%S)"
            if [[ $DRY_RUN -eq 1 ]]; then
                log_info "would backup $dst -> $backup"
            else
                mv "$dst" "$backup"
                log_warn "backed up $dst -> $backup"
            fi
        else
            if [[ $DRY_RUN -eq 1 ]]; then
                log_info "would remove existing $dst"
            else
                rm -rf "$dst"
            fi
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "would link $src -> $dst"
    else
        ln -s "$src" "$dst"
        log_ok "linked $dst"
    fi
}

# Checks if a symlink is broken AND points into $DOTFILES_DIR.
# Returns 0 (removed) or 1 (skipped — not ours, or still working).
_try_remove_link() {
    local link="$1" target
    target="$(readlink "$link")"
    [[ "$target" == "$DOTFILES_DIR"/* ]] || return 1
    [[ -e "$link" ]] && return 1
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "would remove broken link: $link"
    else
        rm "$link"
        log_warn "removed broken link: $link"
    fi
    return 0
}

# --- Config lists ---

COMMON_CONFIGS=(
    zsh
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

MACOS_CONFIGS=(
    rift
)

# --- Installers ---

install_common() {
    log_info "installing common configs"
    local name
    for name in $COMMON_CONFIGS; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
    # zsh bootstrap file — must land directly in $HOME, not .config
    link "$DOTFILES_DIR/zsh/zshenv" "$HOME/.zshenv"
    # starship prompt config — top-level file in .config
    link "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"
}

install_linux() {
    if [[ "$OS" != Linux ]]; then
        log_skip "skipping Linux-only configs (OS: $OS)"
        return 0
    fi

    log_info "installing Linux-only configs"
    local name
    for name in $LINUX_CONFIGS; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
    for name in $LINUX_FILES; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
}

install_macos() {
    if [[ "$OS" != Darwin ]]; then
        log_skip "skipping macOS-only configs (OS: $OS)"
        return 0
    fi

    log_info "installing macOS-only configs"
    local name
    for name in $MACOS_CONFIGS; do
        link "$DOTFILES_DIR/$name" "$HOME/.config/$name"
    done
}

install_gpg() {
    log_info "installing gpg-agent config"
    ensure_dir "$HOME/.gnupg"

    local src="$DOTFILES_DIR/gpg-agent.conf"
    if [[ "$OS" == Darwin ]]; then
        src="$DOTFILES_DIR/gpg-agent.macos.conf"
        log_warn "macOS: ensure pinentry-mac is installed (brew install pinentry-mac)"
    fi
    link "$src" "$HOME/.gnupg/gpg-agent.conf"
}

# --- Main ---

cleanup_broken_links() {
    log_info "scanning for broken dotfiles symlinks"

    # Directories where installers create symlinks (add new locations here).
    local -a SCAN_DIRS=("$HOME/.config" "$HOME/.gnupg")
    local extra
    for extra in "$HOME/projects" "$HOME/.claude" "$HOME/Pictures"; do
        [[ -d "$extra" ]] && SCAN_DIRS+=("$extra")
    done

    local dir link count=0
    # Recursive scan of config dirs + syncthing target locations
    for dir in $SCAN_DIRS; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' link; do
            _try_remove_link "$link" && ((count++))
        done < <(find "$dir" -type l -print0)
    done
    # Shallow scan: $HOME top-level files (e.g. mimeapps.list, electron-flags.conf)
    while IFS= read -r -d '' link; do
        _try_remove_link "$link" && ((count++))
    done < <(find "$HOME" -maxdepth 1 -type l -print0)

    ((count == 0)) && log_skip "no broken dotfiles symlinks found"
    ((count > 0)) && log_ok "cleaned up $count broken link(s)"
}

log_info "OS: $OS"
log_info "dotfiles: $DOTFILES_DIR"
[[ $DRY_RUN -eq 1 ]] && log_info "dry-run mode — no changes will be applied"
[[ $BACKUP -eq 0 ]] && log_warn "backup disabled — existing files will be overwritten"

ensure_dir "$HOME/.config"
cleanup_broken_links

if [[ $_CLEANUP_ONLY -eq 0 ]]; then
    install_common
    install_linux
    install_macos
    install_gpg
fi

# --- Cleanup globals so sourcing doesn't pollute the shell ---

unset DOTFILES_DIR OS DRY_RUN BACKUP _CLEANUP_ONLY
unset COMMON_CONFIGS LINUX_CONFIGS LINUX_FILES MACOS_CONFIGS
unset -f _use_color log_info log_ok log_skip log_warn log_err usage
unset -f ensure_dir link _try_remove_link
unset -f install_common install_linux install_macos install_gpg cleanup_broken_links
