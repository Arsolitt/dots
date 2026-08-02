#!/usr/bin/env zsh

cd /tmp || exit 1

git clone https://aur.archlinux.org/yay.git
cd yay || exit 1
makepkg --syncdeps --install
