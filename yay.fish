#!/usr/bin/env fish

cd /tmp; or exit 1

git clone https://aur.archlinux.org/yay.git
cd yay; or exit 1
makepkg --syncdeps --install
