# tmux cheatsheet (dots/tmux/tmux.conf)

Prefix is `C-a` (Ctrl+A): press, release, then the key.

    C-a C-a     send a literal Ctrl+A to the shell
    C-a ?       full native keybinding list (list-keys)
    C-a h       this cheatsheet in a popup

## Sessions

    C-a d             detach (session keeps running; reattach: tmux attach)
    C-a s             session picker
    C-a $             rename session
    tmux new -A -s main   create-or-attach session "main"

## Windows

    C-a c             new window (inherits current dir)
    C-a w             window tree
    C-a n  /  C-a p   next / previous window
    C-a 0..9          jump to window N
    C-a &             kill window (confirm)
    C-a ,             rename window

## Panes

    C-a |             vertical split (side by side, keeps cwd)
    C-a -             horizontal split (top/bottom, keeps cwd)
    C-a x             kill pane (confirm)
    C-a z             zoom pane (toggle)
    C-a o             cycle panes
    C-a ;             jump to last active pane
    C-a arrows        move focus between panes
    C-a {  /  C-a }   swap panes

## Copy mode (vi style; mouse also works)

    C-a [             enter copy mode (wheel scroll enters too)
      v               begin selection
      y               yank selection and exit (-> system clipboard, OSC52)
      /               search forward
      q               quit copy mode
    C-a ]             paste from buffer

## Plugins & config

    C-a r             reload config
    C-a I             TPM: install plugins
    C-a U             TPM: update plugins

## Good to know

    mouse mode is on — click to focus, drag borders to resize, drag to select
    mouse selection is copied to the system clipboard on release (OSC52)
    Shift+drag = native terminal selection; wheel scrolls 10 lines per notch
    continuum restores previous sessions on tmux server start
    detach-on-destroy is off — closing the last window jumps to another session
    truecolor passthrough is configured for Ghostty and kitty
