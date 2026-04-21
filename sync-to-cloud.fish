#!/usr/bin/env fish

# --- Зависимости ---
for cmd in restic pass
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

set -g PROJECT_EXCLUDES \
    --exclude="**/node_modules" \
    --exclude="**/.next" \
    --exclude="**/.nuxt" \
    --exclude="**/target" \
    --exclude="**/.venv" \
    --exclude="**/venv" \
    --exclude="**/cpython" \
    --exclude="**/dist" \
    --exclude="**/.build" \
    --exclude="**/__pycache__" \
    --exclude="**/*.pyc" \
    --exclude="**/.stignore.*"

# --- Функции ---

function init_repo
    echo "Проверка репозитория..."
    if not restic snapshots $RESTIC_COMMON_ARGS >/dev/null 2>&1
        echo "Инициализация нового репозитория..."
        restic init
    end
end

function run_backup
    set -l src $argv[1]
    set -l extra_args $argv[2..]

    echo "--- Начинаю бэкап: $src ---"

    if restic backup "$src" $RESTIC_COMMON_ARGS $extra_args
        echo "✅ Успешно: $src"
        return 0
    else
        echo "❌ ОШИБКА при бэкапе: $src"
        return 1
    end
end

# --- Основной блок ---

function main
    echo "Запуск скрипта бэкапа Restic..."

    init_repo

    set -l error_count 0

    # Бэкап проектов (тег: projects + группа data для prune)
    run_backup "$HOME/projects/" --tag projects --tag data $PROJECT_EXCLUDES; or set error_count (math $error_count + 1)

    # Бэкап конфигов (тег: уникальный + группа configs для prune)
    run_backup "$HOME/.kube" --tag kube --tag configs --exclude="cache"; or set error_count (math $error_count + 1)
    run_backup "$HOME/.talos" --tag talos --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.ssh" --tag ssh --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.docker" --tag docker --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.gpg" --tag gpg --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.password-store" --tag password-store --tag configs; or set error_count (math $error_count + 1)
    # run_backup "$ZEN_DIR" --tag zen --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/opencode.json" --tag opencode --tag config --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/AGENTS.md" --tag opencode --tag agents --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/superpowers.jsonc" --tag opencode --tag superpowers --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/package.json" --tag opencode --tag packages --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/bun.lock" --tag opencode --tag lock --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.config/opencode/skills" --tag opencode --tag skills --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/rules" --tag claude --tag rules --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/wiki" --tag claude --tag wiki --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/skills" --tag claude --tag skills --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/plugins" --tag claude --tag plugins --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/managed-settings.d" --tag claude --tag managed-settings --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/settings.json" --tag claude --tag settings --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/.claude/commands" --tag claude --tag commands --tag configs; or set error_count (math $error_count + 1)
    run_backup "$HOME/CLAUDE.md" --tag claude --tag md --tag configs; or set error_count (math $error_count + 1)

    # Бэкап медиа
    run_backup "$HOME/Pictures" --tag media; or set error_count (math $error_count + 1)

    echo "=== Выполнение задач завершено ==="

    echo "Запуск очистки (forget/prune)..."
    restic forget --prune --group-by tag --keep-last 3 --tag data
    restic forget --prune --group-by tag --keep-last 3 --tag configs
    restic forget --prune --group-by tag --keep-last 3 --tag media

    if test $error_count -gt 0
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    end
end

main
