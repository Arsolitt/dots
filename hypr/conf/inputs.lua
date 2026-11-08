-- Input configuration

hl.config({
    input = {
        kb_layout = "us, ru",
        -- CapsLock switches layout, Shift+CapsLock keeps CapsLock; Alt+Shift must stay
        -- unclaimed or it swallows app chords such as VSCode copy line down/up
        kb_options = "grp:caps_toggle",
        repeat_rate = 35,
        repeat_delay = 250,
        follow_mouse = 1,
        accel_profile = "flat",
        touchpad = {
            natural_scroll = false,
        },
    },
    -- Uncomment the section below to enable software cursors; this can help with cursor display or behavior issues
    -- cursor = {
    --     no_hardware_cursors = 1,
    -- },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "close" })
hl.gesture({ fingers = 3, direction = "up",         action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "left",       action = "float" })
