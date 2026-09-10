#!/bin/bash

# Wi-Fi: icon-only status, colored by connectivity.

source "$HOME/.config/sketchybar/colors.sh"

SSID=""
if [ "$SENDER" = "wifi_change" ] && [ -n "$INFO" ]; then
  # wifi_change events carry the SSID; trust it when present.
  SSID="$INFO"
else
  AIRPORT=$(networksetup -getairportnetwork en0 2>/dev/null)
  case "$AIRPORT" in
    "Current Wi-Fi Network: "*)
      SSID="${AIRPORT#Current Wi-Fi Network: }"
      ;;
    # Errors, "not associated", or Wi-Fi off all land here.
    *)
      SSID=""
      ;;
  esac
fi

if [ -n "$SSID" ]; then
  sketchybar --set "$NAME" icon="" icon.color=$FOREGROUND # U+F1EB wi-fi
else
  sketchybar --set "$NAME" icon="" icon.color=$DIM # U+F1EB wi-fi
fi
