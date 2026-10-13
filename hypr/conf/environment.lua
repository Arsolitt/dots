hl.env("HYPRCURSOR_THEME", "vimix-kanagawa-hyprcursors-lotus")
hl.env("XCURSOR_THEME", "vimix-kanagawa-cursors-lotus")

hl.env("SSH_AUTH_SOCK", "/run/user/1000/ssh-agent.socket")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_DATA_DIRS", "/usr/share:/usr/local/share")

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")

hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GDK_SCALE", "1")

hl.env("ELECTRON_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

hl.env("SDL_VIDEODRIVER", "wayland,x11,windows")
