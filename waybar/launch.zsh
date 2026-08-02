#!/usr/bin/env zsh

killall waybar
sleep 0.2

waybar &

kill hyprpaper
sleep 0.2
hyprpaper &
