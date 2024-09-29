# if status is-interactive
    # Commands to run in interactive sessions can go here
# end
if status is-login
    # exec Hyprland
end
if status is-login
    if test -z "$DISPLAY" -a "$(tty)" = /dev/tty1
        exec Hyprland
    end
end

set -gx EDITOR nano

zoxide init fish | source
