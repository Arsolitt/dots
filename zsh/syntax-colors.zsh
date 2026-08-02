# syntax-colors.zsh — Kanagawa palette for zsh-syntax-highlighting + autosuggestions.
# Ported from fish/themes/kanagawa.fish.
# Sourced before antidote plugin load so styles are set when plugins initialize.

typeset -A ZSH_HIGHLIGHT_STYLES

# fish_color_normal      (foreground DCD7BA)
ZSH_HIGHLIGHT_STYLES[default]="fg=#DCD7BA"
# fish_color_error       (red C34043)
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=#C34043"
# fish_color_keyword     (pink D27E99) — reserved words: if, then, for, etc.
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=#D27E99"
# fish_color_command     (cyan 7AA89F) — commands, builtins, aliases
ZSH_HIGHLIGHT_STYLES[command]="fg=#7AA89F"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=#7AA89F"
ZSH_HIGHLIGHT_STYLES[alias]="fg=#7AA89F"
ZSH_HIGHLIGHT_STYLES[arg0]="fg=#7AA89F"
# fish_color_param       (purple 957FB8)
ZSH_HIGHLIGHT_STYLES[path]="fg=#957FB8,underline"
ZSH_HIGHLIGHT_STYLES[path_prefix]="fg=#957FB8,underline"
ZSH_HIGHLIGHT_STYLES[path_pathseparator]="fg=#957FB8,underline"
# fish_color_quote       (yellow C0A36E)
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=#C0A36E"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=#C0A36E"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=#C0A36E"
# fish_color_end         (orange FF9E64) — separators, redirections, globs
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=#FF9E64"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=#FF9E64"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=#FF9E64"
# fish_color_comment     (comment 727169)
ZSH_HIGHLIGHT_STYLES[comment]="fg=#727169"
# fish_color_operator    (green 76946A)
ZSH_HIGHLIGHT_STYLES[assign]="fg=#76946A"

# fish_color_autosuggestion (comment 727169) — grey inline ghost-text
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#727169'
# match fish autosuggestion behavior: try history first, then completion
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
