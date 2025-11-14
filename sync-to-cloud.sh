#!/bin/bash

set -euo pipefail

RCLONE_PASSWORD_COMMAND="${RCLONE_PASSWORD_COMMAND:-"pass rclone/config"}"
RCLONE_COMMON_ARGS=(
     --transfers=100
     --checkers=100
     --fast-list
     --multi-thread-streams=32
     --multi-thread-chunk-size=128M
     --buffer-size=64M
     --log-level INFO
     --fix-case
     --progress
     --stats-one-line
)

run_backup() {
    local src="$1"
    local dst="$2"
    local extra_args=("${@:3}") # Все остальные аргументы - это массив

    echo "--- Начинаю бэкап: $src -> $dst ---"
    # Передаем массивы правильно
    if rclone copy "$src" "$dst" "${RCLONE_COMMON_ARGS[@]}" "${extra_args[@]}"; then
        echo "✅ Успешно: $src"
        return 0
    else
        echo "❌ ОШИБКА при бэкапе: $src"
        return 1
    fi
}

main() {
    echo "Запуск скрипта бэкапа..."
    export RCLONE_PASSWORD_COMMAND
    error_count=0

    # Запускаем каждую задачу независимо
    run_backup "$HOME/projects/" "projects:" --exclude="**/{node_modules,.next,target,.venv}/**" --exclude="**/cpython**" || ((error_count++))
    run_backup "$HOME/.kube" "configs:.kube/" --exclude="cache/**" || ((error_count++))
    run_backup "$HOME/.talos" "configs:.talos/" || ((error_count++))
    run_backup "$HOME/.ssh" "configs:.ssh/" || ((error_count++))
    run_backup "$HOME/Pictures" "configs:Pictures/" || ((error_count++))
    run_backup "$HOME/.zen" "configs:.zen/" || ((error_count++))
    run_backup "$HOME/.docker" "configs:.docker/" || ((error_count++))
    run_backup "$HOME/.gpg" "configs:.gpg/" || ((error_count++))

    echo "=== Все задачи бэкапа завершены ==="
    if [ "$error_count" -gt 0 ]; then
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    fi
}

main
