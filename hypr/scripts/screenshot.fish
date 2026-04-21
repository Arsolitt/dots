#!/usr/bin/env fish

function help_message
    echo "Usage: screenshot.fish [options ..] -m [mode] .. -- [command]

Screenshot.fish is a fork of hyprshot with satty integration.

Examples:
  capture a region               \`screenshot.fish -m region\`
  capture and edit active window \`screenshot.fish -m window -m active --edit\`
  capture output with delay      \`screenshot.fish -m output -D 3\`

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
end

function dbg
    if test "$DEBUG" -eq 0
        return 0
    end
    printf $argv 1>&2
end

function trim_geometry
    dbg "Geometry: %s\n" "$argv[1]"
    set -l geometry $argv[1]
    set -l xy_str (echo $geometry | cut -d' ' -f1)
    set -l wh_str (echo $geometry | cut -d' ' -f2)
    set -l x (echo $xy_str | cut -d',' -f1)
    set -l y (echo $xy_str | cut -d',' -f2)
    set -l width (echo $wh_str | cut -dx -f1)
    set -l height (echo $wh_str | cut -dx -f2)

    set -l max_width (hyprctl monitors -j | jq -r '[.[] | if (.transform % 2 == 0) then (.x + .width) else (.x + .height) end] | max')
    set -l max_height (hyprctl monitors -j | jq -r '[.[] | if (.transform % 2 == 0) then (.y + .height) else (.y + .width) end] | max')

    set -l min_x (hyprctl monitors -j | jq -r '[.[] | (.x)] | min')
    set -l min_y (hyprctl monitors -j | jq -r '[.[] | (.y)] | min')

    set -l cropped_x $x
    set -l cropped_y $y
    set -l cropped_width $width
    set -l cropped_height $height

    if test (math "$x + $width") -gt $max_width
        set cropped_width (math "$max_width - $x")
    end
    if test (math "$y + $height") -gt $max_height
        set cropped_height (math "$max_height - $y")
    end

    if test $x -lt $min_x
        set cropped_x $min_x
        set cropped_width (math "$cropped_width + $x - $min_x")
    end
    if test $y -lt $min_y
        set cropped_y $min_y
        set cropped_height (math "$cropped_height + $y - $min_y")
    end

    set -l cropped (printf "%s,%s %sx%s" $cropped_x $cropped_y $cropped_width $cropped_height)
    dbg "Crop: %s\n" $cropped
    echo $cropped
end

function save_geometry
    set -l geometry $argv[1]

    if test "$RAW" -eq 1
        grim -g "$geometry" -
        return 0
    end

    if test "$CLIPBOARD" -eq 0
        mkdir -p $SAVEDIR
        if test "$EDIT" -eq 1
            grim -g "$geometry" - | satty -f - -o - --actions-on-escape=save-to-file,exit | tee $SAVE_FULLPATH | wl-copy
        else
            grim -g "$geometry" - | tee $SAVE_FULLPATH | wl-copy
        end
        set -l output $SAVE_FULLPATH
        if test -n "$COMMAND"
            $COMMAND $output
        end
    else
        if test "$EDIT" -eq 1
            grim -g "$geometry" - | satty -f - -o - --actions-on-escape=save-to-file,exit | wl-copy
        else
            grim -g "$geometry" - | wl-copy --type image/png
        end
    end
end

function check_running
    sleep 1
    while true
        if test (pgrep slurp | wc -m) -eq 0
            pkill hyprpicker
            exit
        end
    end
end

function begin_grab
    if test "$FREEZE" -eq 1; and command -q hyprpicker
        hyprpicker -r -z &
        sleep 0.2
        set -g HYPRPICKER_PID $last_pid
    end

    set -l option $argv[1]
    set -l geometry ""

    switch $option
        case output
            if test "$CURRENT" -eq 1
                set geometry (grab_active_output)
            else if test -z "$SELECTED_MONITOR"
                set geometry (grab_output)
            else
                set geometry (grab_selected_output $SELECTED_MONITOR)
            end
        case region
            set geometry (grab_region)
        case window
            if test "$CURRENT" -eq 1
                set geometry (grab_active_window)
            else
                set geometry (grab_window)
            end
            set geometry (trim_geometry "$geometry")
    end

    if test "$DELAY" -gt 0 2>/dev/null
        sleep $DELAY
    end
    save_geometry "$geometry"
end

function grab_output
    slurp -or
end

function grab_active_output
    set -l active_workspace (hyprctl -j activeworkspace)
    set -l monitors (hyprctl -j monitors)
    dbg "Monitors: %s\n" "$monitors"
    dbg "Active workspace: %s\n" "$active_workspace"
    set -l ws_id (echo $active_workspace | jq -r '.id')
    set -l current_monitor (echo $monitors | jq -r "first(.[] | select(.activeWorkspace.id == $ws_id))")
    dbg "Current output: %s\n" "$current_monitor"
    echo $current_monitor | jq -r '"\(.x),\(.y) \(.width/.scale|round)x\(.height/.scale|round)"'
end

function grab_selected_output
    set -l monitor (hyprctl -j monitors | jq -r ".[] | select(.name == \"$argv[1]\")")
    dbg "Capturing: %s\n" "$argv[1]"
    echo $monitor | jq -r '"\(.x),\(.y) \(.width/.scale|round)x\(.height/.scale|round)"'
end

function grab_region
    slurp -d
end

function grab_window
    set -l monitors (hyprctl -j monitors)
    set -l ws_ids (echo $monitors | jq -r 'map(.activeWorkspace.id) | join(",")')
    set -l clients (hyprctl -j clients | jq -r "[.[] | select(.workspace.id | contains($ws_ids))]")
    dbg "Monitors: %s\n" "$monitors"
    dbg "Clients: %s\n" "$clients"
    set -l boxes (echo $clients | jq -r '.[] | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1]) \(.title)"' | cut -f1,2 -d' ')
    dbg "Boxes:\n%s\n" "$boxes"
    echo $boxes | slurp -r
end

function grab_active_window
    set -l active_window (hyprctl -j activewindow)
    set -l box (echo $active_window | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | cut -f1,2 -d' ')
    dbg "Box:\n%s\n" "$box"
    echo $box
end

function parse_mode
    set -l mode $argv[1]

    switch $mode
        case window region output
            set -g OPTION $mode
        case active
            set -g CURRENT 1
        case '*'
            hyprctl monitors -j | jq -re ".[] | select(.name == \"$mode\")" &>/dev/null
            set -g SELECTED_MONITOR $mode
    end
end

# --- Main script ---

if test (count $argv) -eq 0
    help_message
    exit 0
end

set -g CLIPBOARD 0
set -g DEBUG 0
set -g EDIT 0
set -g RAW 0
set -g CURRENT 0
set -g FREEZE 0
set -g DELAY 0
set -g OPTION ""
set -g SELECTED_MONITOR ""
set -g COMMAND ""
set -g SAVEDIR "$HOME/Pictures/Screenshots"
set -g FILENAME (date +'%Y-%m-%d_%H-%M-%S').png

# Manual argument parsing (fish argparse does not support repeated flags like -m -m)
set -l i 1
while test $i -le (count $argv)
    set -l arg $argv[$i]
    switch $arg
        case -h --help
            help_message
            exit 0
        case -o --output-folder
            set i (math "$i + 1")
            set -g SAVEDIR $argv[$i]
        case -f --filename
            set i (math "$i + 1")
            set -g FILENAME $argv[$i]
        case -D --delay
            set i (math "$i + 1")
            set -g DELAY $argv[$i]
        case -m --mode
            set i (math "$i + 1")
            parse_mode $argv[$i]
        case --clipboard-only
            set -g CLIPBOARD 1
        case -d --debug
            set -g DEBUG 1
        case -e --edit
            set -g EDIT 1
        case -z --freeze
            set -g FREEZE 1
        case -r --raw
            set -g RAW 1
        case --
            # Everything after -- is the command
            set -l next (math "$i + 1")
            if test $next -le (count $argv)
                set -g COMMAND $argv[$next..-1]
            end
            break
    end
    set i (math "$i + 1")
end

if test -z "$OPTION"
    dbg "A mode is required\n\nAvailable modes are:\n\toutput\n\tregion\n\twindow\n"
    exit 2
end

set -g SAVE_FULLPATH "$SAVEDIR/$FILENAME"
if test "$CLIPBOARD" -eq 0
    dbg "Saving in: %s\n" $SAVE_FULLPATH
end

begin_grab $OPTION &
check_running
