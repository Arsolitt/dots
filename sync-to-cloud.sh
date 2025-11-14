#!/bin/bash

COMMAND_ARGS=" --transfers=100 --checkers=100 --fast-list --multi-thread-streams=32 --multi-thread-chunk-size=128M --buffer-size=64M --log-level INFO --fix-case --progress --stats-one-line"

export RCLONE_PASSWORD_COMMAND="pass rclone/config"

# shellcheck disable=SC2086
rclone sync ~/projects/ projects: $COMMAND_ARGS \
  --exclude="**/{node_modules,.next,target,.venv}/**" --exclude="**/cpython**" && \
rclone sync ~/.kube configs:.kube/ $COMMAND_ARGS \
  --exclude="cache/**" && \
rclone sync ~/.talos configs:.talos/ $COMMAND_ARGS && \
rclone sync ~/.ssh configs:.ssh/ $COMMAND_ARGS && \
rclone sync ~/Pictures configs:Pictures/ $COMMAND_ARGS && \
rclone sync ~/.zen configs:.zen/ $COMMAND_ARGS && \
rclone sync ~/.docker configs:.docker/ $COMMAND_ARGS && \
rclone sync ~/.gpg configs:.gpg/ $COMMAND_ARGS
