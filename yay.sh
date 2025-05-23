#!/bin/bash

cd /tmp || exit

git clone https://aur.archlinux.org/yay.git
cd yay || exit
makepkg -si
