#!/bin/bash

# Volume: icon reflects mute level, label shows the percentage.

source "$HOME/.config/sketchybar/colors.sh"

# Click toggles mute; scroll changes volume (SCROLL_DELTA from sketchybar).
case "$SENDER" in
  mouse.clicked)
    osascript -e "set volume output muted not (get volume settings)'s output muted"
    ;;
  mouse.scrolled)
    CUR=$(osascript -e 'output volume of (get volume settings)')
    NEW=$((CUR + SCROLL_DELTA))
    [ "$NEW" -lt 0 ] && NEW=0
    [ "$NEW" -gt 100 ] && NEW=100
    osascript -e "set volume output volume $NEW"
    ;;
esac

VOL=$(osascript -e 'output volume of (get volume settings)')
MUTED=$(osascript -e 'output muted of (get volume settings)')

if [ "$MUTED" = "true" ] || [ "$VOL" -eq 0 ]; then
  ICON="" # U+F026 volume-off
  COLOR=$DIM
elif [ "$VOL" -lt 33 ]; then
  ICON="" # U+F027 volume-down
  COLOR=$FOREGROUND
else
  ICON="" # U+F028 volume-up
  COLOR=$FOREGROUND
fi

sketchybar --set "$NAME" icon="$ICON" icon.color=$COLOR label="$VOL%"
