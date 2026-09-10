#!/bin/bash

# Clock: refreshes the label every update_freq seconds.

source "$HOME/.config/sketchybar/colors.sh"

sketchybar --set "$NAME" label="$(date +'%a %d %b  %H:%M')"
