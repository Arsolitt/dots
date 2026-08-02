#!/usr/bin/env zsh

help_message() {
    echo "Usage: screenshot.zsh [options ..] -m [mode] .. -- [command]

Screenshot.zsh is a fork of hyprshot with satty integration.

Examples:
  capture a region               \`screenshot.zsh -m region\`
  capture and edit active window \`screenshot.zsh -m window -m active --edit\`
  capture output with delay      \`screenshot.zsh -m output -D 3\`

Options:
  -h, --help                show help message
  -m, --mode                one of: output, window, region, active, OUTPUT_NAME
  -o, --output-folder       directory in which to save screenshot
  -f, --filename            the file name of the resulting screenshot
  -D, --delay               how long to delay taking the screenshot after selection (seconds)
  -z, --freeze              freeze the screen on initialization
  -d, --debug               print debug information
  -e, --edit                open screenshot in satty for editing
  -r, --raw                 output raw image data to stdout
  --clipboard-only          copy screenshot to clipboard and don't save image in disk
  -- [command]              open screenshot with a command of your choosing

Modes:
  output        take screenshot of an entire monitor
  window        take screenshot of an open window
  region        take screenshot of selected region
  active        take screenshot of active window|output
                (you must use --mode again with the intended selection)
  OUTPUT_NAME   take screenshot of output with OUTPUT_NAME
                (you must use --mode again with the intended selection)
                (you can get this from \`hyprctl monitors\`)"
}

dbg() {
    if [[ "$DEBUG" -eq 0 ]]; then
        return 0
    fi
    printf "$@" 1>&2
}

trim_geometry() {
    dbg "Geometry: %s\n" "$1"
    local geometry="$1"
    local xy_str="$(echo "$geometry" | cut -d' ' -f1)"
    local wh_str="$(echo "$geometry" | cut -d' ' -f2)"
    local x="$(echo "$xy_str" | cut -d',' -f1)"
    local y="$(echo "$xy_str" | cut -d',' -f2)"
    local width="$(echo "$wh_str" | cut -d'x' -f1)"
    local height="$(echo "$wh_str" | cut -d'x' -f2)"

    local max_width="$(hyprctl monitors -j | jq -r '[.[] | if (.transform % 2 == 0) then (.x + .width) else (.x + .height) end] | max')"
    local max_height="$(hyprctl monitors -j | jq -r '[.[] | if (.transform % 2 == 0) then (.y + .height) else (.y + .width) end] | max')"

    local min_x="$(hyprctl monitors -j | jq -r '[.[] | (.x)] | min')"
    local min_y="$(hyprctl monitors -j | jq -r '[.[] | (.y)] | min')"

    local cropped_x=$x
    local cropped_y=$y
    local cropped_width=$width
    local cropped_height=$height

    if (( x + width > max_width )); then
        cropped_width=$(( max_width - x ))
    fi
    if (( y + height > max_height )); then
        cropped_height=$(( max_height - y ))
    fi

    if (( x < min_x )); then
        cropped_x=$min_x
        cropped_width=$(( cropped_width + x - min_x ))
    fi
    if (( y < min_y )); then
        cropped_y=$min_y
        cropped_height=$(( cropped_height + y - min_y ))
    fi

    local cropped="$(printf "%s,%s %sx%s" "$cropped_x" "$cropped_y" "$cropped_width" "$cropped_height")"
    dbg "Crop: %s\n" "$cropped"
    echo "$cropped"
}

save_geometry() {
    local geometry="$1"

    if [[ "$RAW" -eq 1 ]]; then
        grim -g "$geometry" -
        return 0
    fi

    if [[ "$CLIPBOARD" -eq 0 ]]; then
        mkdir -p "$SAVEDIR"
        if [[ "$EDIT" -eq 1 ]]; then
            grim -g "$geometry" - | satty -f - -o - --actions-on-escape=save-to-file,exit | tee "$SAVE_FULLPATH" | wl-copy
        else
            grim -g "$geometry" - | tee "$SAVE_FULLPATH" | wl-copy
        fi
        local output="$SAVE_FULLPATH"
        if [[ -n "$COMMAND" ]]; then
            $COMMAND "$output"
        fi
    else
        if [[ "$EDIT" -eq 1 ]]; then
            grim -g "$geometry" - | satty -f - -o - --actions-on-escape=save-to-file,exit | wl-copy
        else
            grim -g "$geometry" - | wl-copy --type image/png
        fi
    fi
}

begin_grab() {
    if [[ "$FREEZE" -eq 1 ]] && command -v hyprpicker >/dev/null; then
        hyprpicker -r -z &
        sleep 0.2
        HYPRPICKER_PID=$!
    fi

    local option="$1"
    local geometry=""

    case "$option" in
        output)
            if [[ "$CURRENT" -eq 1 ]]; then
                geometry="$(grab_active_output)"
            elif [[ -z "$SELECTED_MONITOR" ]]; then
                geometry="$(grab_output)"
            else
                geometry="$(grab_selected_output "$SELECTED_MONITOR")"
            fi
            ;;
        region)
            geometry="$(grab_region)"
            ;;
        window)
            if [[ "$CURRENT" -eq 1 ]]; then
                geometry="$(grab_active_window)"
            else
                geometry="$(grab_window)"
            fi
            geometry="$(trim_geometry "$geometry")"
            ;;
    esac

    if [[ "$FREEZE" -eq 1 ]]; then
        pkill hyprpicker
    fi

    if [[ -z "$geometry" ]]; then
        exit 1
    fi

    if (( DELAY > 0 )); then
        sleep "$DELAY"
    fi
    save_geometry "$geometry"
}

grab_output() {
    slurp -or
}

grab_active_output() {
    local active_workspace="$(hyprctl -j activeworkspace)"
    local monitors="$(hyprctl -j monitors)"
    dbg "Monitors: %s\n" "$monitors"
    dbg "Active workspace: %s\n" "$active_workspace"
    local ws_id="$(echo "$active_workspace" | jq -r '.id')"
    local current_monitor="$(echo "$monitors" | jq -r "first(.[] | select(.activeWorkspace.id == $ws_id))")"
    dbg "Current output: %s\n" "$current_monitor"
    echo "$current_monitor" | jq -r '"\(.x),\(.y) \(.width/.scale|round)x\(.height/.scale|round)"'
}

grab_selected_output() {
    local monitor="$(hyprctl -j monitors | jq -r ".[] | select(.name == \"$1\")")"
    dbg "Capturing: %s\n" "$1"
    echo "$monitor" | jq -r '"\(.x),\(.y) \(.width/.scale|round)x\(.height/.scale|round)"'
}

grab_region() {
    slurp -d
}

grab_window() {
    local monitors="$(hyprctl -j monitors)"
    local ws_ids="$(echo "$monitors" | jq -r 'map(.activeWorkspace.id) | join(",")')"
    local clients="$(hyprctl -j clients | jq -r "[.[] | select(.workspace.id | contains($ws_ids))]")"
    dbg "Monitors: %s\n" "$monitors"
    dbg "Clients: %s\n" "$clients"
    local boxes="$(echo "$clients" | jq -r '.[] | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1]) \(.title)"' | cut -f1,2 -d' ')"
    dbg "Boxes:\n%s\n" "$boxes"
    echo "$boxes" | slurp -r
}

grab_active_window() {
    local active_window="$(hyprctl -j activewindow)"
    local box="$(echo "$active_window" | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | cut -f1,2 -d' ')"
    dbg "Box:\n%s\n" "$box"
    echo "$box"
}

parse_mode() {
    local mode="$1"

    case "$mode" in
        window|region|output)
            OPTION="$mode"
            ;;
        active)
            CURRENT=1
            ;;
        *)
            hyprctl monitors -j | jq -re ".[] | select(.name == \"$mode\")" &>/dev/null
            SELECTED_MONITOR="$mode"
            ;;
    esac
}

# --- Main script ---

if [[ $# -eq 0 ]]; then
    help_message
    exit 0
fi

CLIPBOARD=0
DEBUG=0
EDIT=0
RAW=0
CURRENT=0
FREEZE=0
DELAY=0
OPTION=""
SELECTED_MONITOR=""
COMMAND=""
SAVEDIR="$HOME/Pictures/Screenshots"
FILENAME="$(date +'%Y-%m-%d_%H-%M-%S').png"

# Manual argument parsing (fish argparse does not support repeated flags like -m -m)
local i=1
while (( i <= $# )); do
    local arg="${@[$i]}"
    case "$arg" in
        -h|--help)
            help_message
            exit 0
            ;;
        -o|--output-folder)
            i=$(( i + 1 ))
            SAVEDIR="${@[$i]}"
            ;;
        -f|--filename)
            i=$(( i + 1 ))
            FILENAME="${@[$i]}"
            ;;
        -D|--delay)
            i=$(( i + 1 ))
            DELAY="${@[$i]}"
            ;;
        -m|--mode)
            i=$(( i + 1 ))
            parse_mode "${@[$i]}"
            ;;
        --clipboard-only)
            CLIPBOARD=1
            ;;
        -d|--debug)
            DEBUG=1
            ;;
        -e|--edit)
            EDIT=1
            ;;
        -z|--freeze)
            FREEZE=1
            ;;
        -r|--raw)
            RAW=1
            ;;
        --)
            # Everything after -- is the command
            local next=$(( i + 1 ))
            if (( next <= $# )); then
                COMMAND="${@[$next,-1]}"
            fi
            break
            ;;
    esac
    i=$(( i + 1 ))
done

if [[ -z "$OPTION" ]]; then
    dbg "A mode is required\n\nAvailable modes are:\n\toutput\n\tregion\n\twindow\n"
    exit 2
fi

SAVE_FULLPATH="$SAVEDIR/$FILENAME"
if [[ "$CLIPBOARD" -eq 0 ]]; then
    dbg "Saving in: %s\n" "$SAVE_FULLPATH"
fi

begin_grab "$OPTION"
