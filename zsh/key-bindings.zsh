# key-bindings.zsh — fzf + forgit integration.
# fzf is installed at 0.74.1 (≥0.48), so fzf --zsh provides native bindings.

# fzf native key bindings: Ctrl+R (history), Ctrl+T (files), Alt+C (cd)
eval "$(fzf --zsh)"

# fzf-tab (loaded via antidote) replaces Tab menu with fuzzy completion —
# no explicit binding needed, it hooks ^I automatically.

# forgit widgets mapped to fish fzf.fish key sequences.
# Only bind if the functions exist (forgit loaded via antidote).
# Alt+Ctrl+L → git log search (fish: \e\cl)
(( $+functions[forgit_log] ))  && bindkey '^[^l' forgit_log
# Alt+Ctrl+D → git diff search
(( $+functions[forgit_diff] )) && bindkey '^[^d' forgit_diff
