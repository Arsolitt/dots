#!/bin/bash
set -euo pipefail

# --- Конфигурация ---
# Адрес репозитория. Для SSH: sftp:user@host:/path/to/repo
# Убедитесь, что у вас настроен SSH-ключ для беспарольного входа.
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-sftp:pbackup:/mnt/backup/restic}"
export RESTIC_REPOSITORY

# Команда для получения пароля от репозитория
# Restic запросит этот пароль при инициализации и каждом бэкапе
RESTIC_PASSWORD_COMMAND="${RESTIC_PASSWORD_COMMAND:-"pass restic/backup-repo"}"
export RESTIC_PASSWORD_COMMAND

# Общие аргументы restic
# В restic меньше настроек параллелизма, он управляет этим автоматически,
# но можно ограничить скорость при необходимости.
RESTIC_COMMON_ARGS=(
    --verbose
)

# Исключения для projects (развернуты для совместимости с restic glob)
PROJECT_EXCLUDES=(
    --exclude="**/node_modules"
    --exclude="**/.next"
    --exclude="**/.nuxt"
    --exclude="**/target"
    --exclude="**/.venv"
    --exclude="**/venv"
    --exclude="**/cpython"
    --exclude="**/dist"
    --exclude="**/.build"
    --exclude="**/__pycache__"
    --exclude="**/*.pyc"
)

# --- Функции ---

init_repo() {
    echo "Проверка репозитория..."
    # Если команда snapshots падает (репозиторий не существует), инициализируем
    if ! restic snapshots "${RESTIC_COMMON_ARGS[@]}" > /dev/null 2>&1; then
        echo "Инициализация нового репозитория..."
        restic init
    fi
}

run_backup() {
    local src="$1"
    local tag="$2"
    local extra_args=("${@:3}")

    echo "--- Начинаю бэкап: $src (тег: $tag) ---"
    
    # restic backup <путь> --tag <имя_тега> [исключения]
    if restic backup "$src" "${RESTIC_COMMON_ARGS[@]}" --tag "$tag" "${extra_args[@]}"; then
        echo "✅ Успешно: $src"
        return 0
    else
        echo "❌ ОШИБКА при бэкапе: $src"
        return 1
    fi
}

# --- Основной блок ---

main() {
    echo "Запуск скрипта бэкапа Restic..."
    
    # Инициализация репозитория при необходимости
    init_repo

    error_count=0

    # Бэкап проектов с исключениями
    run_backup "$HOME/projects/" "projects" "${PROJECT_EXCLUDES[@]}" || ((error_count++))

    # Бэкап конфигов
    # Rclone создавал папку configs:.kube, restic просто пометит снимок тегом 'configs'
    run_backup "$HOME/.kube" "configs" --exclude="cache" || ((error_count++))
    run_backup "$HOME/.talos" "configs" || ((error_count++))
    run_backup "$HOME/.ssh" "configs" || ((error_count++))
    run_backup "$HOME/.docker" "configs" || ((error_count++))
    run_backup "$HOME/.gpg" "configs" || ((error_count++))
    run_backup "$HOME/.zen" "configs" || ((error_count++))
    run_backup "$HOME/.config/opencode" "configs" || ((error_count++))
    run_backup "$HOME/.claude" "configs" || ((error_count++))
    
    # Медиа и прочее
    run_backup "$HOME/Pictures" "media" || ((error_count++))

    echo "=== Выполнение задач завершено ==="

    # Опционально: очистка старых снапшотов
    # Рекомендуется запускать после бэкапа
    echo "Запуск очистки (forget/prune)..."
    # Пример: хранить последние 5 снапшотов каждого тега, или по времени
    # restic forget --prune --keep-daily 7 --keep-weekly 4 --tag projects || true
    restic forget --prune --keep-last 3 --tag projects
    restic forget --prune --keep-last 3 --tag configs
    restic forget --prune --keep-last 3 --tag media

    if [ "$error_count" -gt 0 ]; then
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    fi
}

main
