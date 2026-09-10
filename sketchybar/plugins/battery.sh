#!/bin/bash

# Battery: glyph by charge level, bolt prefix and color while charging.

source "$HOME/.config/sketchybar/colors.sh"

BATT_INFO=$(pmset -g batt)
PERCENT=$(echo "$BATT_INFO" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
CHARGING=$(echo "$BATT_INFO" | grep -q 'AC Power' && echo 1)

# No battery data (desktop Mac or pmset failure): show a placeholder.
if [ -z "$PERCENT" ]; then
  sketchybar --set "$NAME" icon="" icon.color=$DIM label="--" # U+F244 battery-empty
  exit 0
fi

if [ "$PERCENT" -gt 90 ]; then
  ICON="" # U+F240 battery-full
elif [ "$PERCENT" -gt 60 ]; then
  ICON="" # U+F241 battery-three-quarters
elif [ "$PERCENT" -gt 30 ]; then
  ICON="" # U+F242 battery-half
else
  ICON="" # U+F243 battery-quarter
fi

if [ -n "$CHARGING" ]; then
  # Charging: bolt prefix (U+F0E7), cyan regardless of level.
  ICON="$ICON"
  COLOR=$CYAN
elif [ "$PERCENT" -lt 15 ]; then
  COLOR=$RED
elif [ "$PERCENT" -lt 30 ]; then
  COLOR=$YELLOW
else
  COLOR=$FOREGROUND
fi

sketchybar --set "$NAME" icon="$ICON" icon.color=$COLOR label="$PERCENT%"
