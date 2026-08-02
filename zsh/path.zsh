# path.zsh — PATH construction for all shells.
# Ported from fish/config.fish lines 10-23. nvm logic removed entirely;
# system node + bun are used directly.

typeset -U path  # deduplicate PATH entries

path=(
  $HOME/.local/bin
  $HOME/.cargo/bin
  $HOME/.bun/bin
  $HOME/go/bin
  ${KREW_ROOT:-$HOME}/.krew/bin
  $HOME/vk-cloud-solutions/bin
  $path
)

export BUN_INSTALL="$HOME/.bun"
