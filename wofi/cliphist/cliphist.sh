#!/bin/bash
#   ____ _ _       _     _     _    
#  / ___| (_)_ __ | |__ (_)___| |_  
# | |   | | | '_ \| '_ \| / __| __| 
# | |___| | | |_) | | | | \__ \ |_  
#  \____|_|_| .__/|_| |_|_|___/\__| 
#           |_|                     
#  
# by Stephan Raabe (2023) 
# ----------------------------------------------------- 

# case $1 in
#     d) cliphist list | rofi -dmenu -replace -config ~/dotfiles/rofi/config-cliphist.rasi | cliphist delete
#        ;;

#     w) if [ `echo -e "Clear\nCancel" | rofi -dmenu -config ~/dotfiles/rofi/config-short.rasi` == "Clear" ] ; then
#             cliphist wipe
#        fi
#        ;;

#     *) cliphist list | rofi -dmenu -replace -config ~/dotfiles/rofi/config-cliphist.rasi | cliphist decode | wl-copy
#        ;;
# esac

case $1 in
    d) cliphist list | wofi --dmenu -c ~/.config/wofi/cliphist/config-main -s ~/.config/wofi/cliphist/style.css | cliphist delete
       ;;

    w) if [ `echo -e "Cancel\nClear" | wofi -d -c ~/.config/wofi/cliphist/config-select -s ~/.config/wofi/cliphist/style.css` == "Clear" ] ; then
            cliphist wipe
       fi
       ;;

    *) cliphist list | wofi --dmenu -c ~/.config/wofi/cliphist/config-main -s ~/.config/wofi/cliphist/style.css | cliphist decode | wl-copy
       ;;
esac