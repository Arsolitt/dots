#!/usr/bin/env zsh
#
# Dotfiles installer. Symlinks configs into $HOME, skipping
# Linux-only configs when running on macOS.

emulate -L zsh

DOTFILES_DIR="${0:A:h}"
OS="$(uname -s)"
DRY_RUN=0
BACKUP=1

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
    printf 'Usage: %s [--dry-run] [--no-backup] [--help]\n' "${script:t}"
    printf '\n'
    printf 'Symlinks dotfiles into $HOME. Skips Linux-only configs on macOS.\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --dry-run     Print what would be done without making changes.\n'
    printf '  --no-backup   Overwrite existing files/links instead of backing them up.\n'
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

install_syncthing() {
    log_info "installing Syncthing .stignore files"

    local -a ST_NAMES=(projects claude opencode pictures)
    local -a ST_DESTS=(
        "$HOME/projects"
        "$HOME/.claude"
        "$HOME/.config/opencode"
        "$HOME/Pictures"
    )
    local -a DEV_FOLDERS=(projects)

    local i name dest dev
    for ((i = 1; i <= ${#ST_NAMES[@]}; i++)); do
        name="${ST_NAMES[$i]}"
        dest="${ST_DESTS[$i]}"
        ensure_dir "$dest"
        link "$DOTFILES_DIR/syncthing/default.stignore" "$dest/.stignore.default"
        link "$DOTFILES_DIR/syncthing/$name.stignore" "$dest/.stignore"
    done

    for dev in $DEV_FOLDERS; do
        for ((i = 1; i <= ${#ST_NAMES[@]}; i++)); do
            if [[ "${ST_NAMES[$i]}" == "$dev" ]]; then
                link "$DOTFILES_DIR/syncthing/dev.stignore" "${ST_DESTS[$i]}/.stignore.dev"
                break
            fi
        done
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

log_info "OS: $OS"
log_info "dotfiles: $DOTFILES_DIR"
[[ $DRY_RUN -eq 1 ]] && log_info "dry-run mode — no changes will be applied"
[[ $BACKUP -eq 0 ]] && log_warn "backup disabled — existing files will be overwritten"

ensure_dir "$HOME/.config"
install_common
install_linux
install_macos
install_gpg
install_syncthing

log_ok done

# --- Cleanup globals so sourcing doesn't pollute the shell ---

unset DOTFILES_DIR OS DRY_RUN BACKUP
unset COMMON_CONFIGS LINUX_CONFIGS LINUX_FILES MACOS_CONFIGS
unset -f _use_color log_info log_ok log_skip log_warn log_err usage
unset -f ensure_dir link
unset -f install_common install_linux install_macos install_syncthing install_gpg
