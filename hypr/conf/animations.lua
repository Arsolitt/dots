-- Default curves and animations, see https://wiki.hypr.land/configuring/core/animations/

-- Default beziers
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("overshoot",      { type = "bezier", points = { {0.5, 0.9},   {0.1, 1.1}   } })

-- Default springs (speed is ignored for springs; stiffness/damping set the duration)
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 700, damping = 41.4 })
hl.curve("rubber",         { type = "spring", mass = 1, stiffness = 280, damping = 18   })

-- Animations
hl.animation({ leaf = "global",              enabled = true, speed = 2,   bezier = "quick"                  })
hl.animation({ leaf = "windows",             enabled = true, speed = 2.5, spring = "easy",  style = "slide" })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 3,   bezier = "quick", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 1.5, bezier = "quick", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.5, bezier = "quick", style = "slide bottom" })
