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

# --- Функции ---

# $1 = тег снапшота, $2 = куда восстанавливать, $3+ = возможные относительные пути от $HOME
run_restore() {
    local tag="$1"
    local dest="$2"
    shift 2

    echo "--- Восстановление: $dest (тег: $tag) ---"

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    if restic restore latest \
        "${RESTIC_COMMON_ARGS[@]}" \
        --tag "$tag" \
        --target "$tmp_dir"; then
        mkdir -p "$dest"

        # В снапшоте полный путь: /home/user/.kube → tmp_dir/home/user/.kube
        # Находим корень старого home и копируем нужную поддиректорию
        local old_root
        old_root="$(find "$tmp_dir" -mindepth 2 -maxdepth 2 -type d | head -n 1)"

        for rel_path in "$@"; do
            if [ -d "$old_root/$rel_path" ]; then
                cp -Rp "$old_root/$rel_path/." "$dest"
                break
            fi
        done

        rm -rf "$tmp_dir"
        echo "✅ Успешно: $dest"
        return 0
    else
        rm -rf "$tmp_dir"
        echo "❌ ОШИБКА при восстановлении: $dest"
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
    run_restore "projects" "$HOME/projects/" "projects" || ((error_count++))

    # Конфиги
    run_restore "kube" "$HOME/.kube" ".kube" || ((error_count++))
    run_restore "talos" "$HOME/.talos" ".talos" || ((error_count++))
    run_restore "ssh" "$HOME/.ssh" ".ssh" || ((error_count++))
    run_restore "docker" "$HOME/.docker" ".docker" || ((error_count++))
    run_restore "gpg" "$HOME/.gpg" ".gpg" || ((error_count++))
    run_restore "zen" "$ZEN_DIR" ".zen" "Library/Application Support/zen" || ((error_count++))
    run_restore "opencode" "$HOME/.config/opencode" ".config/opencode" || ((error_count++))
    run_restore "claude" "$HOME/.claude" ".claude" || ((error_count++))

    # Медиа
    run_restore "media" "$HOME/Pictures" "Pictures" || ((error_count++))

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
