#!/usr/bin/env bash
set -euo pipefail

# --- Зависимости ---
for cmd in restic pass; do
    command -v "$cmd" &>/dev/null || { echo "Ошибка: $cmd не найден. Установите его сначала."; exit 1; }
done

# --- Платформа ---
case "$(uname -s)" in
    Darwin) ZEN_DIR="$HOME/Library/Application Support/zen" ;;
    *)      ZEN_DIR="$HOME/.zen" ;;
esac

# --- Конфигурация ---
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-sftp:pbackup:/mnt/backup/restic}"
export RESTIC_REPOSITORY

RESTIC_PASSWORD_COMMAND="${RESTIC_PASSWORD_COMMAND:-"pass restic/backup-repo"}"
export RESTIC_PASSWORD_COMMAND

RESTIC_COMMON_ARGS=(
    --verbose
)

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
    if ! restic snapshots "${RESTIC_COMMON_ARGS[@]}" > /dev/null 2>&1; then
        echo "Инициализация нового репозитория..."
        restic init
    fi
}

run_backup() {
    local src="$1"
    shift

    echo "--- Начинаю бэкап: $src ---"

    if restic backup "$src" "${RESTIC_COMMON_ARGS[@]}" "$@"; then
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

    init_repo

    error_count=0

    # Бэкап проектов (тег: projects + группа data для prune)
    run_backup "$HOME/projects/" --tag projects --tag data "${PROJECT_EXCLUDES[@]}" || ((error_count++))

    # Бэкап конфигов (тег: уникальный + группа configs для prune)
    run_backup "$HOME/.kube" --tag kube --tag configs --exclude="cache" || ((error_count++))
    run_backup "$HOME/.talos" --tag talos --tag configs || ((error_count++))
    run_backup "$HOME/.ssh" --tag ssh --tag configs || ((error_count++))
    run_backup "$HOME/.docker" --tag docker --tag configs || ((error_count++))
    run_backup "$HOME/.gpg" --tag gpg --tag configs || ((error_count++))
    run_backup "$HOME/.password-store" --tag password-store --tag configs || ((error_count++))
    # run_backup "$ZEN_DIR" --tag zen --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/opencode.json" --tag opencode --tag config --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/AGENTS.md" --tag opencode --tag agents --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/superpowers.jsonc" --tag opencode --tag superpowers --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/package.json" --tag opencode --tag packages --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/bun.lock" --tag opencode --tag lock --tag configs || ((error_count++))
    run_backup "$HOME/.config/opencode/skills" --tag opencode --tag skills --tag configs || ((error_count++))
    run_backup "$HOME/.claude/rules" --tag claude --tag rules --tag configs || ((error_count++))
    run_backup "$HOME/.claude/wiki" --tag claude --tag wiki --tag configs || ((error_count++))
    run_backup "$HOME/.claude/skills" --tag claude --tag skills --tag configs || ((error_count++))
    run_backup "$HOME/.claude/plugins" --tag claude --tag plugins --tag configs || ((error_count++))
    run_backup "$HOME/.claude/managed-settings.d" --tag claude --tag managed-settings --tag configs || ((error_count++))
    run_backup "$HOME/.claude/settings.json" --tag claude --tag settings --tag configs || ((error_count++))
    run_backup "$HOME/.claude/commands" --tag claude --tag commands --tag configs || ((error_count++))
    run_backup "$HOME/CLAUDE.md" --tag claude --tag md --tag configs || ((error_count++))

    # Бэкап медиа
    run_backup "$HOME/Pictures" --tag media || ((error_count++))

    echo "=== Выполнение задач завершено ==="

    echo "Запуск очистки (forget/prune)..."
    restic forget --prune --group-by tag --keep-last 3 --tag data
    restic forget --prune --group-by tag --keep-last 3 --tag configs
    restic forget --prune --group-by tag --keep-last 3 --tag media

    if [ "$error_count" -gt 0 ]; then
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    fi
}

main
