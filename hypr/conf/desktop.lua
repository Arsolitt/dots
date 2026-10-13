hl.monitor({ output = "HDMI-A-1", mode = "1920x1200@60", position = "-1920x0", scale = 1, transform = 2 })
hl.monitor({ output = "DP-2", mode = "3440x1440@165", position = "0x0", scale = 1 })

hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-2", persistent = true, gaps_in = 5 })
hl.workspace_rule({ workspace = "3", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2", persistent = true, gaps_in = 2 })
hl.workspace_rule({ workspace = "5", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1", persistent = true })
hl.workspace_rule({ workspace = "7", monitor = "HDMI-A-1", persistent = true })

hl.curve("easeOutQuart", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("easeOutCubic", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "easeOutCubic", style = "popin" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "easeOutCubic", style = "popin 80%" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "easeOutCubic" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuart", style = "fade" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "easeOutCubic" })

hl.env("HYPRCURSOR_SIZE", "32")
hl.env("XCURSOR_SIZE", "32")
