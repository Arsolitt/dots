# .zshrc — interactive shells only.

# ─── History ───────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=$ZDOTDIR/.zsh_history
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE INC_APPEND_HISTORY

# ─── Directory navigation ───────────────────────────────────
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS

# ─── Completion ─────────────────────────────────────────────
setopt MENU_COMPLETE NO_BEEP
autoload -Uz compinit && compinit -d $ZDOTDIR/.zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'  # case-insensitive

# ─── Source chain (ORDER IS CRITICAL) ───────────────────────

# 1. Kanagawa palette vars (before plugins read highlight styles)
source "$ZDOTDIR/syntax-colors.zsh"

# 2. antidote bootstrap + plugin load
#    self-cloning: antidote is vendored into $ZDOTDIR/.antidote (gitignored)
if [[ ! -d "$ZDOTDIR/.antidote" ]]; then
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ZDOTDIR/.antidote"
fi
source "$ZDOTDIR/.antidote/antidote.zsh"
antidote load

# 3. aliases (simple fish wrappers)
source "$ZDOTDIR/aliases.zsh"

# 4. functions (complex fish functions + dynamic git commands)
source "$ZDOTDIR/functions.zsh"

# 5. abbreviations (after zsh-abbr is loaded via antidote)
#    session scope (-S in the files) + quiet mode for clean startup
ABBR_QUIETER=1
source "$ZDOTDIR/git-abbrs.zsh"
source "$ZDOTDIR/k8s-abbrs.zsh"

# 6. key bindings (fzf integration)
source "$ZDOTDIR/key-bindings.zsh"

# 7. zoxide (cd replacement)
eval "$(zoxide init zsh)"

# 8. starship prompt (LAST — must render after all widgets/plugins)
eval "$(starship init zsh)"
