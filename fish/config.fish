if status is-interactive
    # Commands to run in interactive sessions can go here
end
if status is-login
    exec Hyprland
end
set -gx EDITOR nano

zoxide init fish | source
