#!/bin/bash

case $1 in
    d) cliphist list | wofi --dmenu -c ~/.config/dots/wofi/cliphist/config-main -s ~/.config/dots/wofi/cliphist/style.css | cliphist delete
       ;;

    w) if [ `echo -e "Cancel\nClear" | wofi -d -c ~/.config/dots/wofi/cliphist/config-select -s ~/.config/dots/wofi/cliphist/style.css` == "Clear" ] ; then
            cliphist wipe
       fi
       ;;

    *) cliphist list | wofi --dmenu -c ~/.config/dots/wofi/cliphist/config-main -s ~/.config/dots/wofi/cliphist/style.css | cliphist decode | wl-copy
       ;;
esac