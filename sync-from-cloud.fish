#!/usr/bin/env fish

# --- Зависимости ---
for cmd in restic pass rsync jq
    if not command --query $cmd
        echo "Ошибка: $cmd не найден. Установите его сначала."
        exit 1
    end
end

# --- Платформа ---
switch (uname -s)
    case Darwin
        set -g ZEN_DIR "$HOME/Library/Application Support/zen"
    case '*'
        set -g ZEN_DIR "$HOME/.zen"
end

# --- Конфигурация ---
if not set --query RESTIC_REPOSITORY
    set -gx RESTIC_REPOSITORY "sftp:pbackup:/mnt/backup/restic"
end

if not set --query RESTIC_PASSWORD_COMMAND
    set -gx RESTIC_PASSWORD_COMMAND "pass restic/backup-repo"
end

set -g RESTIC_COMMON_ARGS --verbose

# --- Функции ---

# $argv[1] = тег снапшота, $argv[2] = куда восстанавливать
function run_restore
    set -l tag $argv[1]
    set -l dest $argv[2]

    echo "--- Восстановление: $dest (тег: $tag) ---"

    set -l original_path (restic snapshots --tag "$tag" --latest 1 --json \
        | jq --raw-output '.[0].paths[0] // empty')

    if test -z "$original_path"
        echo "❌ Не удалось определить путь из снапшота (тег: $tag)"
        return 1
    end

    set -l cache_dir "$HOME/.cache/restic-restore/$tag"
    mkdir -p "$cache_dir"

    if not restic restore latest \
            $RESTIC_COMMON_ARGS \
            --tag "$tag" \
            --target "$cache_dir" \
            --overwrite if-changed
        echo "❌ ОШИБКА при восстановлении: $dest"
        return 1
    end

    set -l restored_path "$cache_dir$original_path"
    if test -d "$restored_path"
        mkdir -p "$dest"
        rsync --archive "$restored_path/" "$dest/"
    else if test -f "$restored_path"
        mkdir -p (dirname "$dest")
        rsync --archive "$restored_path" "$dest"
    else
        echo "❌ Восстановленный путь не найден: $restored_path"
        return 1
    end

    echo "✅ Успешно: $dest"
end

function list_snapshots
    echo "Доступные снапшоты:"
    restic snapshots $RESTIC_COMMON_ARGS --compact
    echo
end

# --- Основной блок ---

function main
    echo "⚠️  ВНИМАНИЕ! ⚠️"
    echo "Вы собираетесь восстановить данные из бэкапа."
    echo "Существующие файлы будут ПЕРЕЗАПИСАНЫ."
    echo

    list_snapshots

    read --prompt-str "Вы уверены, что хотите продолжить? (Введите 'yes' для подтверждения): " confirmation
    if test "$confirmation" != yes
        echo "Операция отменена."
        exit 0
    end

    echo "Запуск восстановления..."

    set -l error_count 0

    # Проекты
    run_restore projects "$HOME/projects/"; or set error_count (math $error_count + 1)

    # Конфиги
    run_restore kube "$HOME/.kube"; or set error_count (math $error_count + 1)
    run_restore talos "$HOME/.talos"; or set error_count (math $error_count + 1)
    run_restore ssh "$HOME/.ssh"; or set error_count (math $error_count + 1)
    run_restore docker "$HOME/.docker"; or set error_count (math $error_count + 1)
    run_restore gpg "$HOME/.gpg"; or set error_count (math $error_count + 1)
    run_restore password-store "$HOME/.password-store"; or set error_count (math $error_count + 1)
    # run_restore zen "$ZEN_DIR"; or set error_count (math $error_count + 1)
    run_restore opencode,config "$HOME/.config/opencode/opencode.json"; or set error_count (math $error_count + 1)
    run_restore opencode,agents "$HOME/.config/opencode/AGENTS.md"; or set error_count (math $error_count + 1)
    run_restore opencode,superpowers "$HOME/.config/opencode/superpowers.jsonc"; or set error_count (math $error_count + 1)
    run_restore opencode,packages "$HOME/.config/opencode/package.json"; or set error_count (math $error_count + 1)
    run_restore opencode,lock "$HOME/.config/opencode/bun.lock"; or set error_count (math $error_count + 1)
    run_restore opencode,skills "$HOME/.config/opencode/skills"; or set error_count (math $error_count + 1)
    run_restore claude,rules "$HOME/.claude/rules"; or set error_count (math $error_count + 1)
    run_restore claude,wiki "$HOME/.claude/wiki"; or set error_count (math $error_count + 1)
    run_restore claude,skills "$HOME/.claude/skills"; or set error_count (math $error_count + 1)
    run_restore claude,plugins "$HOME/.claude/plugins"; or set error_count (math $error_count + 1)
    run_restore claude,managed-settings "$HOME/.claude/managed-settings.d"; or set error_count (math $error_count + 1)
    run_restore claude,settings "$HOME/.claude/settings.json"; or set error_count (math $error_count + 1)
    run_restore claude,commands "$HOME/.claude/commands"; or set error_count (math $error_count + 1)
    run_restore claude,md "$HOME/CLAUDE.md"; or set error_count (math $error_count + 1)

    # Медиа
    run_restore media "$HOME/Pictures"; or set error_count (math $error_count + 1)

    echo "=== Восстановление завершено ==="

    if test $error_count -gt 0
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все данные успешно восстановлены!"
        exit 0
    end
end

main
