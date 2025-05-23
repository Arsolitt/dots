if status is-login
    if test -z "$DISPLAY" -a "$(tty)" = /dev/tty1
        exec Hyprland
    end
end

set -gx EDITOR nano

zoxide init fish | source
set -q KREW_ROOT; and set -gx PATH $PATH $KREW_ROOT/.krew/bin; or set -gx PATH $PATH $HOME/.krew/bin
# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
source ~/.config/fish/themes/kanagawa.fish
