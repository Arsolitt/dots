# .zshenv — sourced for ALL shells (interactive, non-interactive, login, non-login).
# Manually sourced from the bootstrap ~/.zshenv (zsh does not auto-read
# $ZDOTDIR/.zshenv when ~/.zshenv set ZDOTDIR mid-startup).

source "$ZDOTDIR/path.zsh"
source "$ZDOTDIR/env.zsh"
