MONITOR1 = "DP-2"
MONITOR2 = "HDMI-A-1"
MONITOR3 = ""
PRIMARY_MONITOR = MONITOR1
NUM_WPM = 7

hl.monitor({ output = "DP-2", mode = "3440x1440@165", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1200@60", position = "-1920x0", scale = 1, transform = 2 })

hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-2", persistent = true, gaps_in = 5 })
hl.workspace_rule({ workspace = "3", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2", persistent = true, gaps_in = 2 })
hl.workspace_rule({ workspace = "5", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1", persistent = true })
hl.workspace_rule({ workspace = "7", monitor = "HDMI-A-1", persistent = true })

hl.device({ name = "xctech-wireless-receiver", sensitivity = -0.5 })

hl.env("HYPRCURSOR_SIZE", "32")
hl.env("XCURSOR_SIZE", "32")
