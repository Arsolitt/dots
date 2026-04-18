#!/usr/bin/env bash
set -euo pipefail

# --- Зависимости ---
for cmd in restic pass; do
    command -v "$cmd" &>/dev/null || { echo "Ошибка: $cmd не найден. Установите его сначала."; exit 1; }
done

# --- Конфигурация ---
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-sftp:pbackup:/mnt/backup/restic}"
export RESTIC_REPOSITORY

RESTIC_PASSWORD_COMMAND="${RESTIC_PASSWORD_COMMAND:-"pass restic/backup-repo"}"
export RESTIC_PASSWORD_COMMAND

RESTIC_COMMON_ARGS=(
    --verbose
)

# --- Функции ---

run_restore() {
    local tag="$1"
    local path="$2"
    local extra_args=("${@:3}")

    echo "--- Восстановление: $path (тег: $tag) ---"

    # --path фильтрует снапшот по пути бэкапа, --target / восстанавливает в оригинальное расположение
    if restic restore latest \
        "${RESTIC_COMMON_ARGS[@]}" \
        --tag "$tag" \
        --path "$path" \
        --target / \
        "${extra_args[@]}"; then
        echo "✅ Успешно: $path"
        return 0
    else
        echo "❌ ОШИБКА при восстановлении: $path"
        return 1
    fi
}

list_snapshots() {
    echo "Доступные снапшоты:"
    restic snapshots "${RESTIC_COMMON_ARGS[@]}" --compact
    echo
}

# --- Основной блок ---

main() {
    echo "⚠️  ВНИМАНИЕ! ⚠️"
    echo "Вы собираетесь восстановить данные из бэкапа."
    echo "Существующие файлы будут ПЕРЕЗАПИСАНЫ."
    echo

    list_snapshots

    read -p "Вы уверены, что хотите продолжить? (Введите 'yes' для подтверждения): " confirmation
    if [ "$confirmation" != "yes" ]; then
        echo "Операция отменена."
        exit 0
    fi

    echo "Запуск восстановления..."

    error_count=0

    # Проекты
    run_restore "projects" "$HOME/projects/" || ((error_count++))

    # Конфиги
    run_restore "configs" "$HOME/.kube" --exclude="cache" || ((error_count++))
    run_restore "configs" "$HOME/.talos" || ((error_count++))
    run_restore "configs" "$HOME/.ssh" || ((error_count++))
    run_restore "configs" "$HOME/.docker" || ((error_count++))
    run_restore "configs" "$HOME/.gpg" || ((error_count++))
    run_restore "configs" "$HOME/.zen" || ((error_count++))
    run_restore "configs" "$HOME/.config/opencode" || ((error_count++))
    run_restore "configs" "$HOME/.claude" || ((error_count++))

    # Медиа
    run_restore "media" "$HOME/Pictures" || ((error_count++))

    echo "=== Восстановление завершено ==="

    if [ "$error_count" -gt 0 ]; then
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все данные успешно восстановлены!"
        exit 0
    fi
}

main
