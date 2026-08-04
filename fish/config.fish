if status is-login
    if test (uname) = Linux -a -z "$DISPLAY" -a "$(tty)" = /dev/tty1
        exec start-hyprland
    end
end

set -gx GPG_TTY (tty)
set -gx EDITOR nano

set --export PATH $PATH ~/vk-cloud-solutions/bin

set --export PATH $PATH ~/go/bin

zoxide init fish | source
set -q KREW_ROOT; and set -gx PATH $PATH $KREW_ROOT/.krew/bin; or set -gx PATH $PATH $HOME/.krew/bin

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
# cargo
set --export PATH ~/.cargo/bin $PATH
# fnm (Node version manager — replaces nvm.fish)
type -q fnm; and fnm env --use-on-cd | source
source ~/.config/fish/themes/kanagawa.fish
fish_add_path $HOME/.local/bin

# starship prompt (replaces tide) — must init last
starship init fish | source
