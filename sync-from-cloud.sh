#!/bin/bash

COMMAND_ARGS=" --transfers=100 --checkers=100 --fast-list --multi-thread-streams=32 --multi-thread-chunk-size=128M --buffer-size=64M --log-level INFO --fix-case --progress --stats-one-line"

export RCLONE_PASSWORD_COMMAND="pass rclone/config"

# shellcheck disable=SC2086
rclone sync projects: ~/projects/ $COMMAND_ARGS \
  --exclude="**/{node_modules,.next,target,.venv}/**" --exclude="**/cpython**" && \
rclone sync configs:.kube/ ~/.kube $COMMAND_ARGS \
  --exclude="cache/**" && \
rclone sync configs:.talos/ ~/.talos $COMMAND_ARGS && \
rclone sync configs:.ssh/ ~/.ssh $COMMAND_ARGS && \
rclone sync configs:Pictures/ ~/Pictures $COMMAND_ARGS && \
rclone sync configs:.zen/ ~/.zen $COMMAND_ARGS && \
rclone sync configs:.docker/ ~/.docker $COMMAND_ARGS && \
rclone sync configs:.gpg/ ~/.gpg $COMMAND_ARGS
