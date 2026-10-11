# machine-paths.fish — machine-local values that the shared fish_variables must not hold
#
# fish_variables is committed to the dots repo and synced between macOS and Linux.
# Universal path values would flip-flop between /Users/... and /home/... on every
# sync, so they live here instead, resolved from $HOME at session scope.
# Loaded before z.fish (alphabetical order), whose store init then stays a no-op.

set -g Z_DATA_DIR $HOME/.local/share/z
set -g Z_DATA $Z_DATA_DIR/data
set -g Z_EXCLUDE "^$HOME\$"

if not contains -- $HOME/.local/bin $fish_user_paths
    set -g fish_user_paths $HOME/.local/bin $fish_user_paths
end
