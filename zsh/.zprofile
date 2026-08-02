# .zprofile — login shells only.
# Ported from fish/config.fish lines 1-5: auto-start Hyprland on tty1.

if [[ "$(uname)" == "Linux" ]] && [[ -z "$DISPLAY" ]] && [[ "$(tty)" == /dev/tty1 ]]; then
  exec start-hyprland
fi
