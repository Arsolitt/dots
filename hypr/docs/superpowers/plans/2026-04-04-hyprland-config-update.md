# Hyprland Config Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update Hyprland config to match current best practices: remove deprecated hyprscrolling plugin, fix bugs, add animations and binds settings.

**Architecture:** Incremental edits to existing config files under `~/.config/dots/hypr/`. No new files needed except removing plugin dependency.

**Tech Stack:** Hyprland config syntax (v3)

---

### Task 1: Remove hyprscrolling plugin and replace with native scrolling block

**Files:**
- Modify: `conf/autostart.conf:6`
- Modify: `conf/misc.conf:13-19`

- [ ] **Step 1: Remove plugin load from autostart**

In `conf/autostart.conf`, delete the line:
```
exec-once = hyprctl plugin load /usr/lib/hyprscrolling.so
```

- [ ] **Step 2: Replace plugin block with native scrolling block**

In `conf/misc.conf`, replace:
```
plugin {
    hyprscrolling {
        fullscreen_on_one_column = true
        column_width = 0.5
        explicit_column_widths = 0.333, 0.5, 0.667, 1.0
        focus_fit_method = 1
    }
}
```

with:
```
scrolling {
    fullscreen_on_one_column = true
    column_width = 0.5
    explicit_column_widths = 0.333, 0.5, 0.667, 1.0
    focus_fit_method = 1
}
```

- [ ] **Step 3: Commit**

```bash
git add conf/autostart.conf conf/misc.conf
git commit -m "chore: remove hyprscrolling plugin, use native scrolling layout"
```

---

### Task 2: Fix environment variable bug

**Files:**
- Modify: `conf/environment.conf:21`

- [ ] **Step 1: Fix broken SDL_VIDEODRIVER line**

In `conf/environment.conf`, replace:
```
env = export SDL_VIDEODRIVER, 'wayland,x11,windows'
```

with:
```
env = SDL_VIDEODRIVER, wayland,x11,windows
```

- [ ] **Step 2: Commit**

```bash
git add conf/environment.conf
git commit -m "fix: remove export and quotes from SDL_VIDEODRIVER env var"
```

---

### Task 3: Fix monitor and workspace issues

**Files:**
- Modify: `conf/desktop/workspaces.conf:8`
- Modify: `conf/desktop/workspaces.conf:3`
- Modify: `conf/laptop/workspaces.conf:3`

- [ ] **Step 1: Fix nonexistent monitor in desktop workspaces**

In `conf/desktop/workspaces.conf`, replace:
```
workspace = 7, monitor:HDMI-A-2, persistent:true
```

with:
```
workspace = 7, monitor:HDMI-A-1, persistent:true
```

- [ ] **Step 2: Fix trailing comma in desktop workspaces**

In `conf/desktop/workspaces.conf`, replace:
```
workspace = 2, monitor:DP-2, persistent:true,gapsin:5,
```

with:
```
workspace = 2, monitor:DP-2, persistent:true,gapsin:5
```

- [ ] **Step 3: Fix trailing comma in laptop workspaces**

In `conf/laptop/workspaces.conf`, replace:
```
workspace = 2, monitor:eDP-1, persistent:true,gapsin:5,
```

with:
```
workspace = 2, monitor:eDP-1, persistent:true,gapsin:5
```

- [ ] **Step 4: Commit**

```bash
git add conf/desktop/workspaces.conf conf/laptop/workspaces.conf
git commit -m "fix: correct monitor name and remove trailing commas in workspaces"
```

---

### Task 4: Fix hyprlock deprecated general block

**Files:**
- Modify: `hyprlock.conf:18-23`

- [ ] **Step 1: Remove deprecated general block**

In `hyprlock.conf`, delete the entire `general { ... }` block:
```
# GENERAL
general {
    no_fade_in = false
    no_fade_out = false
    grace = 0
    disable_loading_bar = false
}
```

- [ ] **Step 2: Commit**

```bash
git add hyprlock.conf
git commit -m "chore: remove deprecated hyprlock general block"
```

---

### Task 5: Fix decoration boolean style

**Files:**
- Modify: `conf/decorations.conf:6`

- [ ] **Step 1: Replace `on` with `true`**

In `conf/decorations.conf`, replace:
```
new_optimizations = on
```

with:
```
new_optimizations = true
```

- [ ] **Step 2: Commit**

```bash
git add conf/decorations.conf
git commit -m "style: use true/false instead of on/off in decoration blur"
```

---

### Task 6: Add animations

**Files:**
- Modify: `conf/desktop/workspaces.conf:10-11`
- Modify: `conf/laptop/workspaces.conf:9-10`

- [ ] **Step 1: Add animations to desktop workspaces**

In `conf/desktop/workspaces.conf`, replace:
```
bezier=test,0,0,0,0
animation=workspaces,1,3.5,test,fade
```

with:
```
bezier=easeOutQuart,0.25,1,0.5,1
bezier=easeOutCubic,0.33,1,0.68,1

animation = windows, 1, 3, easeOutCubic, popin
animation = windowsOut, 1, 3, easeOutCubic, popin 80%
animation = fade, 1, 4, easeOutCubic
animation = workspaces, 1, 4, easeOutQuart, slidefadevert
animation = border, 1, 3, easeOutCubic
```

- [ ] **Step 2: Add same animations to laptop workspaces**

In `conf/laptop/workspaces.conf`, replace:
```
bezier=test,0,0,0,0
animation=workspaces,1,3.5,test,fade
```

with the same content:
```
bezier=easeOutQuart,0.25,1,0.5,1
bezier=easeOutCubic,0.33,1,0.68,1

animation = windows, 1, 3, easeOutCubic, popin
animation = windowsOut, 1, 3, easeOutCubic, popin 80%
animation = fade, 1, 4, easeOutCubic
animation = workspaces, 1, 4, easeOutQuart, slidefadevert
animation = border, 1, 3, easeOutCubic
```

- [ ] **Step 3: Commit**

```bash
git add conf/desktop/workspaces.conf conf/laptop/workspaces.conf
git commit -m "feat: add minimalist window and workspace animations"
```

---

### Task 7: Add binds settings

**Files:**
- Create: `conf/binds.conf`
- Modify: `hyprland.conf`
- Modify: `laptop.hyprland.conf`
- Modify: `desktop.hyprland.conf`

- [ ] **Step 1: Create binds.conf**

Create `conf/binds.conf` with:
```
binds {
    workspace_back_and_forth = true
    focus_preferred_method = 1
    movefocus_cycles_fullscreen = false
}
```

- [ ] **Step 2: Source binds.conf in hyprland.conf**

In `hyprland.conf`, add after the `source = ~/.config/hypr/conf/misc.conf` line:
```
source = ~/.config/hypr/conf/binds.conf
```

- [ ] **Step 3: Source binds.conf in laptop.hyprland.conf**

In `laptop.hyprland.conf`, add after the `source = ~/.config/hypr/conf/misc.conf` line:
```
source = ~/.config/hypr/conf/binds.conf
```

- [ ] **Step 4: Source binds.conf in desktop.hyprland.conf**

In `desktop.hyprland.conf`, add after the `source = ~/.config/hypr/conf/misc.conf` line:
```
source = ~/.config/hypr/conf/binds.conf
```

- [ ] **Step 5: Commit**

```bash
git add conf/binds.conf hyprland.conf laptop.hyprland.conf desktop.hyprland.conf
git commit -m "feat: add binds section with workspace_back_and_forth and focus settings"
```

---

## Summary of all changes

| Task | What | File(s) |
|------|------|---------|
| 1 | Remove hyprscrolling plugin → native scrolling | `autostart.conf`, `misc.conf` |
| 2 | Fix SDL_VIDEODRIVER env var | `environment.conf` |
| 3 | Fix monitor name + trailing commas | `desktop/workspaces.conf`, `laptop/workspaces.conf` |
| 4 | Remove deprecated hyprlock general block | `hyprlock.conf` |
| 5 | Fix `on` → `true` in blur | `decorations.conf` |
| 6 | Add minimalist animations | `desktop/workspaces.conf`, `laptop/workspaces.conf` |
| 7 | Add binds settings | `conf/binds.conf`, all 3 main `.conf` files |
