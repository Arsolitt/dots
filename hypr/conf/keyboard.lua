local mainMod = "SUPER"
local noctCall = "noctalia msg "
local shotScript = os.getenv("HOME") .. "/.config/hypr/scripts/screenshot.fish"

-- --- Applications -----------------------------------------------------------------------------------------

hl.bind(mainMod .. " + F1",     hl.dsp.exec_cmd("zen-browser", { tile = true }))
hl.bind(mainMod .. " + F2",     hl.dsp.exec_cmd(TERMINAL))
hl.bind(mainMod .. " + F3",     hl.dsp.exec_cmd(EDITOR))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(FILE_MANAGER))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(TERMINAL))
hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd(BROWSER))
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd(EDITOR))
hl.bind(mainMod .. " + C",      hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd(CALCULATOR))
hl.bind("XF86Calculator",       hl.dsp.exec_cmd(CALCULATOR))

-- --- Windows ----------------------------------------------------------------------------------------------

hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + space",  hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + J",      hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + P",      hl.dsp.window.pin())
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprpicker -a -n"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- Focus ------------------------------------------------------------------------------------------------

hl.bind(mainMod .. " + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + Down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + Left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + Up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + Down",  hl.dsp.window.move({ direction = "d" }))

hl.bind("ALT + Tab",         hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd(noctCall .. "window-switcher"))

-- --- Scrolling layout -------------------------------------------------------------------------------------

hl.bind(mainMod .. " + A", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + D", hl.dsp.layout("move +col"))
hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + mouse_up", hl.dsp.layout("move +col"))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.layout("colresize -conf"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.layout("colresize +conf"))
hl.bind(mainMod .. " + SHIFT + mouse_up", hl.dsp.layout("colresize -conf"))
hl.bind(mainMod .. " + SHIFT + mouse_down", hl.dsp.layout("colresize +conf"))
hl.bind(mainMod .. " + CONTROL + A", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + CONTROL + D", hl.dsp.layout("swapcol r"))
hl.bind(mainMod .. " + CONTROL + mouse_up", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.layout("swapcol r"))

-- --- Workspaces -------------------------------------------------------------------------------------------

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + CONTROL + Right", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + Left",  hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + Down",  hl.dsp.focus({ workspace = "emptym" }))

hl.bind(mainMod .. " + CONTROL + SHIFT + Right", hl.dsp.window.move({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + Left",  hl.dsp.window.move({ workspace = "m-1" }))

-- --- Scratchpad -------------------------------------------------------------------------------------------

hl.bind(mainMod .. " + grave",         hl.dsp.workspace.toggle_special())
hl.bind(mainMod .. " + SHIFT + grave", hl.dsp.window.move({ workspace = "special" }))

-- --- Noctalia ---------------------------------------------------------------------------------------------

hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher"))
hl.bind(mainMod .. " + X",         hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center"))
hl.bind(mainMod .. " + N",         hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center notifications"))
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd(noctCall .. "settings-toggle"))
hl.bind(mainMod .. " + ALT + C",   hl.dsp.exec_cmd(noctCall .. "panel-toggle session"))
hl.bind(mainMod .. " + V",         hl.dsp.exec_cmd(noctCall .. "panel-toggle clipboard"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(noctCall .. "panel-toggle wallpaper"))
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd(noctCall .. "session lock"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(noctCall .. "bar-toggle"))
hl.bind(mainMod .. " + M",         hl.dsp.exit())

-- --- Screenshots ------------------------------------------------------------------------------------------

hl.bind("Print",                hl.dsp.exec_cmd(shotScript .. " -m region -z"))
hl.bind("CONTROL + Print",      hl.dsp.exec_cmd(shotScript .. " -m region --edit -z"))
hl.bind("SHIFT + Print",        hl.dsp.exec_cmd(shotScript .. " -m window -m active -z"))
hl.bind("CONTROL + SHIFT + Print", hl.dsp.exec_cmd(shotScript .. " -m window -m active --edit -z"))
hl.bind(mainMod .. " + Print",  hl.dsp.exec_cmd(shotScript .. " -m output -m active -z"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd(shotScript .. " -m output -m active --edit -z"))

-- --- Recording --------------------------------------------------------------------------------------------

hl.bind(mainMod .. " + Next", hl.dsp.exec_cmd([[pkill wf-recorder || wf-recorder -g "$(slurp)" --framerate 60 -f $HOME/Videos/Screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4]]))
hl.bind(mainMod .. " + SHIFT + Next", hl.dsp.exec_cmd([[pkill wf-recorder || wf-recorder --audio="pactl list sources short | grep RUNNING | awk '{print $2}'" --framerate 60 -f $HOME/Videos/Screencasts/$(date +'%Y-%m-%d_%H-%M-%S').mp4 -o DP-2]]))

-- --- Zoom -------------------------------------------------------------------------------------------------

local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end

hl.bind(mainMod .. " + Minus", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + Plus",  function() zoomfunction(0.3) end, { repeating = true })

-- --- Media & backlight ------------------------------------------------------------------------------------

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(noctCall .. "volume-up"),      { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(noctCall .. "volume-down"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(noctCall .. "volume-mute"),    { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd(noctCall .. "mic-mute"),       { locked = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true })
hl.bind("XF86AudioPause",        hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd(noctCall .. "media next"))
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd(noctCall .. "media previous"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(noctCall .. "brightness-up"),  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctCall .. "brightness-down"), { locked = true, repeating = true })
