#!/usr/bin/fish

# ANSI names only: colors follow whatever 16-color palette kitty currently
# renders, which noctalia derives from its active palette. No hex values here.

# Syntax Highlighting Colors
set -g fish_color_normal normal
set -g fish_color_command blue
set -g fish_color_keyword purple
set -g fish_color_quote green
set -g fish_color_redirection yellow
set -g fish_color_end green
set -g fish_color_error red
set -g fish_color_param cyan
set -g fish_color_comment brblack
set -g fish_color_cancel red
set -g fish_color_selection --background=brblack
set -g fish_color_search_match --background=brblack
set -g fish_color_operator blue
set -g fish_color_escape cyan
set -g fish_color_autosuggestion brblack

# Completion Pager Colors
set -g fish_pager_color_progress brblack
set -g fish_pager_color_prefix blue
set -g fish_pager_color_completion normal
set -g fish_pager_color_description yellow
