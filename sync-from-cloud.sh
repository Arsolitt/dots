#!/usr/bin/env bash
set -euo pipefail

# --- Зависимости ---
for cmd in restic pass rsync jq; do
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

# --- Функции ---

# $1 = тег снапшота, $2 = куда восстанавливать
run_restore() {
    local tag="$1"
    local dest="$2"

    echo "--- Восстановление: $dest (тег: $tag) ---"

    local original_path
    original_path="$(restic snapshots --tag "$tag" --latest 1 --json \
        | jq --raw-output '.[0].paths[0] // empty')"

    if [ -z "$original_path" ]; then
        echo "❌ Не удалось определить путь из снапшота (тег: $tag)"
        return 1
    fi

    local cache_dir="$HOME/.cache/restic-restore/$tag"
    mkdir -p "$cache_dir"

    if ! restic restore latest \
        "${RESTIC_COMMON_ARGS[@]}" \
        --tag "$tag" \
        --target "$cache_dir" \
        --overwrite if-changed; then
        echo "❌ ОШИБКА при восстановлении: $dest"
        return 1
    fi

    local restored_path="$cache_dir$original_path"
    if [ -d "$restored_path" ]; then
        mkdir -p "$dest"
        rsync --archive "$restored_path/" "$dest/"
    elif [ -f "$restored_path" ]; then
        mkdir -p "$(dirname "$dest")"
        rsync --archive "$restored_path" "$dest"
    else
        echo "❌ Восстановленный путь не найден: $restored_path"
        return 1
    fi

    echo "✅ Успешно: $dest"
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
    run_restore "kube" "$HOME/.kube" || ((error_count++))
    run_restore "talos" "$HOME/.talos" || ((error_count++))
    run_restore "ssh" "$HOME/.ssh" || ((error_count++))
    run_restore "docker" "$HOME/.docker" || ((error_count++))
    run_restore "gpg" "$HOME/.gpg" || ((error_count++))
    run_restore "password-store" "$HOME/.password-store" || ((error_count++))
    # run_restore "zen" "$ZEN_DIR" || ((error_count++))
    run_restore "opencode,config" "$HOME/.config/opencode/opencode.json" || ((error_count++))
    run_restore "opencode,agents" "$HOME/.config/opencode/AGENTS.md" || ((error_count++))
    run_restore "opencode,superpowers" "$HOME/.config/opencode/superpowers.jsonc" || ((error_count++))
    run_restore "opencode,packages" "$HOME/.config/opencode/package.json" || ((error_count++))
    run_restore "opencode,lock" "$HOME/.config/opencode/bun.lock" || ((error_count++))
    run_restore "opencode,skills" "$HOME/.config/opencode/skills" || ((error_count++))
    run_restore "claude,rules" "$HOME/.claude/rules" || ((error_count++))
    run_restore "claude,settings" "$HOME/.claude/settings.json" || ((error_count++))
    run_restore "claude,commands" "$HOME/.claude/commands" || ((error_count++))
    run_restore "claude,md" "$HOME/CLAUDE.md" || ((error_count++))

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
