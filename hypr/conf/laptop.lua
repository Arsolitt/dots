MONITOR1 = "eDP-1"
MONITOR2 = "HDMI-A-1"
MONITOR3 = ""
PRIMARY_MONITOR = MONITOR1
NUM_WPM = 5

hl.monitor({ output = "eDP-1", mode = "2560x1600@120", position = "0x0", scale = 1.6 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1200@60", position = "-1440x125", scale = 1.33333 })

hl.workspace_rule({ workspace = "1", monitor = "eDP-1", default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "eDP-1", persistent = true, gaps_in = 5 })
hl.workspace_rule({ workspace = "3", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "eDP-1", persistent = true, gaps_in = 2 })
hl.workspace_rule({ workspace = "5", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1", persistent = true })

hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("systemctl suspend"), { locked = true })

hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")
