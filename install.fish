#!/usr/bin/env fish
#
# install.fish — idempotent dotfiles bootstrap installer.
#
# Installs packages (macOS via Homebrew, Arch Linux via pacman/yay),
# symlinks configs, sets up fisher/fnm/krew, and sets the default shell.
# Safe to re-run: every action is guarded by an idempotency check.
#
# Prerequisites — the fish shell itself must be available first:
#   macOS:  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install fish
#   Arch:   sudo pacman -S fish
#
# Usage:
#   fish install.fish            # run for real
#   fish install.fish --dry-run  # print planned actions, change nothing

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

# fish builtins only — no realpath dependency on a fresh machine.
set -g DOTFILES (path dirname (path resolve (status filename)))
set -g OS (uname -s)            # Darwin | Linux
set -g DRY_RUN 0
set -g ERRORS 0

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

argparse --name=install 'h/help' 'dry-run' -- $argv
or begin
    printf 'error: bad arguments — try \'fish install.fish --help\'\n' >&2
    exit 2
end

if set --query _flag_help
    printf 'Usage: fish install.fish [--dry-run] [--help]\n'
    printf '\n'
    printf 'Idempotent dotfiles installer (macOS + Arch Linux).\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --dry-run   Print planned actions without making changes.\n'
    printf '  --help      Show this message.\n'
    printf '\n'
    printf 'Detected:\n'
    printf '  OS          %s\n' $OS
    printf '  Dotfiles    %s\n' $DOTFILES
    exit 0
end

set --query _flag_dry_run; and set DRY_RUN 1

# ---------------------------------------------------------------------------
# Logging helpers (same style as links.fish)
# ---------------------------------------------------------------------------

function _use_color
    isatty stdout
end

function _log_info
    if _use_color
        set_color blue; printf '==>'; set_color normal
    else
        printf '==>'
    end
    printf ' %s\n' "$argv"
end

function _log_ok
    if _use_color
        set_color green; printf ' +'; set_color normal
    else
        printf ' +'
    end
    printf '  %s\n' "$argv"
end

function _log_skip
    if _use_color
        set_color brblack; printf ' .'; set_color normal
        printf '  '
        set_color brblack; printf '%s' "$argv"; set_color normal
    else
        printf ' .  %s\n' "$argv"
    end
    printf '\n'
end

function _log_warn
    if _use_color
        set_color yellow; printf ' !'; set_color normal
    else
        printf ' !'
    end
    printf '  %s\n' "$argv"
end

function _log_err
    if _use_color
        set_color red; printf ' x'; set_color normal
    else
        printf ' x'
    end
    printf '  %s\n' "$argv" >&2
    set -g ERRORS (math $ERRORS + 1)
end

function _have
    command -v $argv[1] >/dev/null 2>&1
end

# ---------------------------------------------------------------------------
# Phase 1: packages
# ---------------------------------------------------------------------------

function _phase1_packages
    _log_info "phase 1: packages ($OS)"
    switch $OS
        case Darwin
            _install_packages_macos
        case Linux
            _install_packages_linux
        case '*'
            _log_err "unsupported OS: $OS"
    end
end

function _install_packages_macos
    if not _have brew
        _log_err "Homebrew not found — install it first:"
        _log_err "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    end

    # kubernetes-cli provides the `kubectl` binary — use the canonical name for
    # both install and the list-check so the idempotency probe never false-misses.
    # `rustup` (not the oldname rustup-init) installs the rustup-init binary.
    set -l formulas starship zoxide eza bat fd fzf git jq cloc fnm kubernetes-cli \
        go gnupg restic pass rsync rust cilium-cli kubecm pinentry-mac
    set -l missing
    for pkg in $formulas
        if brew list --formula "$pkg" >/dev/null 2>&1
            _log_skip "brew: $pkg already installed"
        else
            set -a missing $pkg
        end
    end
    if test (count $missing) -gt 0
        if test $DRY_RUN -eq 1
            _log_info "would brew install: $missing"
        else
            brew install $missing
            if test $status -eq 0
                for pkg in $missing; _log_ok "brew: installed $pkg"; end
            else
                _log_err "brew install failed: $missing"
            end
        end
    end

    # flux — needs its own tap
    if brew list --formula fluxcd/tap/flux >/dev/null 2>&1
        _log_skip "brew: flux already installed"
    else if test $DRY_RUN -eq 1
        _log_info "would brew tap fluxcd/tap && brew install fluxcd/tap/flux"
    else
        brew tap fluxcd/tap
        and brew install fluxcd/tap/flux
        if test $status -eq 0
            _log_ok "brew: installed flux"
        else
            _log_err "brew: flux install failed"
        end
    end
end

function _install_packages_linux
    set -l repo_pkgs starship zoxide eza bat fd fzf git jq cloc fnm kubectl \
        go gnupg restic pass rsync rust cilium-cli
    set -l missing
    for pkg in $repo_pkgs
        if pacman -Q "$pkg" >/dev/null 2>&1
            _log_skip "pacman: $pkg already installed"
        else
            set -a missing $pkg
        end
    end
    if test (count $missing) -gt 0
        if test $DRY_RUN -eq 1
            _log_info "would pacman -S --needed: $missing"
        else
            sudo pacman -S --needed --noconfirm -- $missing
            if test $status -eq 0
                for pkg in $missing; _log_ok "pacman: installed $pkg"; end
            else
                _log_err "pacman install failed: $missing"
            end
        end
    end

    # flux — AUR (fluxcd) via yay
    if pacman -Q fluxcd >/dev/null 2>&1
        _log_skip "aur: fluxcd already installed"
    else if not _have yay
        _log_warn "yay not found — install fluxcd manually: yay -S fluxcd"
    else if test $DRY_RUN -eq 1
        _log_info "would yay -S fluxcd"
    else
        yay -S --needed --noconfirm fluxcd
        if test $status -eq 0
            _log_ok "aur: installed fluxcd"
        else
            _log_err "aur: fluxcd install failed"
        end
    end

    # kubecm — not in pacman, not in krew; install from GitHub releases
    _install_kubecm_linux
end

function _install_kubecm_linux
    if _have kubecm
        _log_skip "kubecm: already installed"
        return 0
    end

    set -l tag (curl -fsSL --max-time 20 \
        https://api.github.com/repos/sunny0826/kubecm/releases/latest | jq -r .tag_name)
    if test -z "$tag" -o "$tag" = null
        _log_err "kubecm: could not resolve latest release"
        return 1
    end

    # kubecm asset scheme: kubecm_<TAG>_<OS>_<ARCH>.tar.gz
    #   OS capitalized (Linux/Darwin); ARCH keeps x86_64 (arm64 for aarch64/arm64); TAG keeps the leading v.
    set -l os (uname -s)
    set -l arch (uname -m)
    switch $arch
        case aarch64 arm64
            set arch arm64
    end
    set -l asset "kubecm"_"$tag"_"$os"_"$arch".tar.gz
    set -l url "https://github.com/sunny0826/kubecm/releases/download/$tag/$asset"

    if test $DRY_RUN -eq 1
        _log_info "would install kubecm $tag from $url"
        return 0
    end

    set -l tmp (mktemp -d)
    pushd "$tmp" >/dev/null
    set -l st 1
    curl -fsSLo kubecm.tar.gz "$url"
    and tar xf kubecm.tar.gz
    and sudo install -m 0755 kubecm /usr/local/bin/kubecm
    set st $status
    popd >/dev/null
    rm -rf "$tmp"
    if test $st -eq 0
        _log_ok "kubecm: installed $tag"
    else
        _log_err "kubecm: install failed ($url)"
    end
end

# ---------------------------------------------------------------------------
# Phase 2: symlink configs
# ---------------------------------------------------------------------------

function _phase2_links
    _log_info "phase 2: symlink configs"
    if test $DRY_RUN -eq 1
        fish "$DOTFILES/links.fish" --dry-run
    else
        fish "$DOTFILES/links.fish"
    end
    if test $status -eq 0
        _log_ok "symlinks reconciled"
    else
        _log_err "links.fish reported a failure"
    end
end

# ---------------------------------------------------------------------------
# Phase 3: fisher
# ---------------------------------------------------------------------------

function _phase3_fisher
    _log_info "phase 3: fisher"

    if functions --query fisher 2>/dev/null; or test -f "$DOTFILES/fish/functions/fisher.fish"
        _log_skip "fisher: already installed"
    else if test $DRY_RUN -eq 1
        _log_info "would install fisher"
    else
        curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
        and fisher install jorgebucaran/fisher
        if test $status -eq 0
            _log_ok "fisher: installed"
        else
            _log_err "fisher: install failed"
        end
    end

    # Always reconcile plugins (idempotent — also prunes stale sdkman/nvm if present live).
    if test $DRY_RUN -eq 1
        _log_info "would run: fisher update"
        return 0
    end
    fisher update
    if test $status -eq 0
        _log_ok "fisher: plugins reconciled"
    else
        _log_warn "fisher: update reported issues (may be harmless)"
    end
end

# ---------------------------------------------------------------------------
# Phase 4: fnm + node
# ---------------------------------------------------------------------------

function _phase4_fnm
    _log_info "phase 4: fnm + node"

    if not _have fnm
        if test $DRY_RUN -eq 1
            _log_info "would install node via fnm (fnm installed in phase 1)"
            return 0
        end
        _log_err "fnm not found — phase 1 should have installed it"
        return 1
    end

    # fnm list prints one line per installed version; empty => nothing installed.
    set -l vers (fnm list 2>/dev/null)
    if test (count $vers) -gt 0
        _log_skip "fnm: node already installed"
        return 0
    end

    if test $DRY_RUN -eq 1
        _log_info "would fnm install --lts && fnm default lts-latest"
        return 0
    end

    fnm install --lts
    and fnm default lts-latest
    if test $status -eq 0
        _log_ok "fnm: installed node LTS"
    else
        _log_err "fnm: node install failed"
    end
end

# ---------------------------------------------------------------------------
# Phase 5: krew
# ---------------------------------------------------------------------------

function _phase5_krew
    _log_info "phase 5: krew"

    if test -x "$HOME/.krew/bin/kubectl-krew"
        _log_skip "krew: already installed"
        return 0
    end

    if test $DRY_RUN -eq 1
        _log_info "would install krew"
        return 0
    end

    # krew asset scheme: krew-<os>_<arch>.tar.gz (lowercase os, amd64 for x86_64).
    set -l os (string lower (uname -s))
    set -l arch (uname -m)
    switch $arch
        case x86_64
            set arch amd64
        case aarch64 arm64
            set arch arm64
    end
    set -l krew_bin "krew-$os"_"$arch"

    set -l tmp (mktemp -d)
    pushd "$tmp" >/dev/null
    set -l st 1
    curl -fsSLo krew.tar.gz "https://github.com/kubernetes-sigs/krew/releases/latest/download/$krew_bin.tar.gz"
    and tar xf krew.tar.gz
    and ./$krew_bin install krew
    set st $status
    popd >/dev/null
    rm -rf "$tmp"
    if test $st -eq 0
        _log_ok "krew: installed"
    else
        _log_err "krew: install failed"
    end
end

# ---------------------------------------------------------------------------
# Phase 6: default shell
# ---------------------------------------------------------------------------

function _phase6_shell
    _log_info "phase 6: default shell"

    set -l fish_bin (command -v fish)
    if test -z "$fish_bin"
        _log_err "fish not found in PATH"
        return 1
    end
    if test "$SHELL" = "$fish_bin"
        _log_skip "default shell already fish"
        return 0
    end

    if test $DRY_RUN -eq 1
        _log_info "would chsh -s $fish_bin (and add to /etc/shells)"
        return 0
    end

    if not grep -qx -- "$fish_bin" /etc/shells 2>/dev/null
        echo "$fish_bin" | sudo tee -a /etc/shells >/dev/null
        _log_ok "added $fish_bin to /etc/shells"
    end
    chsh -s "$fish_bin"
    if test $status -eq 0
        _log_ok "default shell set to fish — relogin to apply"
    else
        _log_err "chsh failed"
    end
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

_log_info "OS: $OS"
_log_info "dotfiles: $DOTFILES"
test $DRY_RUN -eq 1; and _log_info "DRY-RUN — no changes will be applied"

_phase1_packages
_phase2_links
_phase3_fisher
_phase4_fnm
_phase5_krew
_phase6_shell

# ---------------------------------------------------------------------------
# Summary & cleanup
# ---------------------------------------------------------------------------

if test $ERRORS -eq 0
    _log_ok "all done — run 'exec fish' (or relogin) to apply"
else
    _log_warn "$ERRORS error(s) reported above — review before relying on this environment"
end

set --erase DOTFILES OS DRY_RUN ERRORS
functions --erase _use_color _log_info _log_ok _log_skip _log_warn _log_err _have
functions --erase _phase1_packages _install_packages_macos _install_packages_linux _install_kubecm_linux
functions --erase _phase2_links _phase3_fisher _phase4_fnm _phase5_krew _phase6_shell
