#!/bin/bash

cd /tmp || exit

git clone https://aur.archlinux.org/yay.git
cd yay || exit
makepkg -si

xargs yay -S < packages.txt

ln -sf "$PWD"/fish "$HOME"/.config/fish
ln -sf "$PWD"/mimeapps.list "$HOME"/.config/mimeapps.list
ln -sf "$PWD"/gtk-2.0 "$HOME"/.config/gtk-2.0
ln -sf "$PWD"/gtk-3.0 "$HOME"/.config/gtk-3.0
ln -sf "$PWD"/hypr "$HOME"/.config/hypr
ln -sf "$PWD"/kitty "$HOME"/.config/kitty
ln -sf "$PWD"/nwg-look "$HOME"/.config/nwg-look
ln -sf "$PWD"/swappy "$HOME"/.config/swappy
ln -sf "$PWD"/swayimg "$HOME"/.config/swayimg
ln -sf "$PWD"/swaylock "$HOME"/.config/swaylock
ln -sf "$PWD"/wlogout "$HOME"/.config/wlogout
ln -sf "$PWD"/wofi "$HOME"/.config/wofi
ln -sf "$PWD"/hyprpanel "$HOME"/.config/hyprpanel
ln -sf "$PWD"/electron-flags.conf "$HOME"/.config/electron-flags.conf
