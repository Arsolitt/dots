#!/usr/bin/env fish

# XWayland rebases Hyprland's negative coordinates to 0,0 and marks the leftmost
# output primary. With the secondary monitor on the left, Wine enumerates its
# mode list and games cannot select the gaming monitor's native resolution.
# Pin MONITOR1 once XWayland is up.

set -l output $argv[1]
if test -z "$output"
    exit 1
end

for i in (seq 1 300)
    if xrandr --output $output --primary 2>/dev/null
        exit 0
    end
    sleep 1
end

exit 1
