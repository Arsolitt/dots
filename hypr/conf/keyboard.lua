hl.config({
    input = {
        kb_layout = "us, ru",
        kb_options = "grp:alt_shift_toggle",
        repeat_rate = 35,
        repeat_delay = 250,
        follow_mouse = 1,
        touchpad = {
            natural_scroll = false
        },
        sensitivity = -0.5
    }
})

-- SUPER KEY
local mainMod = "SUPER"
local terminal = "kitty"

-- Applications
hl.bind(mainMod .. " + f1", hl.dsp.exec_cmd("zen-browser", { tile = true }))
hl.bind(mainMod .. " + f2", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + f3", hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nemo"))

-- Windows
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + space", hl.dsp.window.float())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + P", hl.dsp.window.pin())
-- hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
-- hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
-- hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
-- hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
-- hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
-- hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
-- hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

hl.bind(mainMod .. " + A", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + D", hl.dsp.layout("move +col"))
hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + mouse_up", hl.dsp.layout("move +col"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.layout("colresize -conf"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.layout("colresize +conf"))
hl.bind(mainMod .. " + SHIFT + mouse_up", hl.dsp.layout("colresize -conf"))
hl.bind(mainMod .. " + SHIFT + mouse_down", hl.dsp.layout("colresize +conf"))
hl.bind(mainMod .. " + CTRL + A", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + CTRL + D", hl.dsp.layout("swapcol r"))
hl.bind(mainMod .. " + CTRL + mouse_up", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.layout("swapcol r"))

-- Screen recording

hl.bind(mainMod .. " + Next", hl.dsp.exec_cmd([[pkill wf-recorder || wf-recorder -g "$(slurp)" --framerate 60 -f $HOME/Videos/Screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4]]))
hl.bind(mainMod .. " + SHIFT + Next", hl.dsp.exec_cmd([[pkill wf-recorder || wf-recorder --audio="pactl list sources short | grep RUNNING | awk '{print $2}'" --framerate 60 -f $HOME/Videos/Screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4 -o DP-2]]))

-- Screenshots GRIM SLURP WL-COPY
-- hl.bind("End", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))
-- hl.bind("CTRL + End", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f - -o - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))
-- hl.bind("SHIFT + End", hl.dsp.exec_cmd([[grim -g "$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))
-- hl.bind("CTRL + SHIFT + End", hl.dsp.exec_cmd([[grim -g "$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" - | swappy -f - -o - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))
-- hl.bind(mainMod .. " + End", hl.dsp.exec_cmd([[grim -o "$(hyprctl -j activeworkspace | jq -r '(.monitor)')" - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))
-- hl.bind(mainMod .. " + SHIFT + End", hl.dsp.exec_cmd([[grim -o "$(hyprctl -j activeworkspace | jq -r '(.monitor)')" - | swappy -f - -o - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png | wl-copy]]))

-- Screenshot hyprshot
local hyprshotScript = os.getenv("HOME") .. "/.config/hypr/scripts/screenshot.fish"
hl.bind("Print", hl.dsp.exec_cmd(hyprshotScript .. " -m region -z"))
hl.bind("CTRL + Print", hl.dsp.exec_cmd(hyprshotScript .. " -m region --edit -z"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(hyprshotScript .. " -m window -m active -z"))
hl.bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd(hyprshotScript .. " -m window -m active --edit -z"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(hyprshotScript .. " -m output -m active -z"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd(hyprshotScript .. " -m output -m active --edit -z"))

hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("~/.config/rofi/launchers/type-1/launcher.sh"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("~/.config/rofi/applets/bin/apps.sh"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("~/.config/waybar/launch.fish"))
hl.bind(mainMod .. " + M", hl.dsp.exit())
-- hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("~/.config/wofi/cliphist/cliphist.sh"))

-- Workspaces
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
-- hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e+1" }))
-- hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
-- hl.bind(mainMod .. " + CTRL + down", hl.dsp.focus({ workspace = "empty" }))

-- Fn keys
-- hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s +10%"))
-- hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 10%-"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"))
-- hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
-- hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"))
-- hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
-- hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
-- hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"))
-- hl.bind("XF86Calculator", hl.dsp.exec_cmd("qalculate-gtk"))
-- hl.bind("XF86Lock", hl.dsp.exec_cmd("swaylock"))
-- hl.bind("XF86Tools", hl.dsp.exec_cmd("alacritty --class dotfiles-floating -e ~/dotfiles/hypr/settings/settings.sh"))

-- Passthrough SUPER KEY to Virtual Machine
-- bind = $mainMod, P, submap, passthru
-- submap = passthru
-- bind = SUPER, Escape, submap, reset
-- submap = reset
