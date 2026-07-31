#!/usr/bin/env fish

# --- Зависимости ---
for cmd in restic pass jq
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

# --- Реестр целей (единый источник истины для бэкапа и cleanup) ---
# path | source_tag | category_tag ("" если нет) | excludes (строка через пробел, БЕЗ пробелов внутри значений)

function _t
    set -g -a T_PATHS  $argv[1]
    set -g -a T_SRCTAG $argv[2]
    set -g -a T_CATTAG $argv[3]
    set -g -a T_EXCL   $argv[4]
end

function define_targets
    set -g T_PATHS
    set -g T_SRCTAG
    set -g T_CATTAG
    set -g T_EXCL

    _t "$HOME/projects/"        projects       data    (string join ' ' -- $PROJECT_EXCLUDES)
    _t "$HOME/.kube"            kube           configs "--exclude=cache"
    _t "$HOME/.talos"           talos          configs ""
    _t "$HOME/.ssh"             ssh            configs ""
    _t "$HOME/.docker"          docker         configs ""
    _t "$HOME/.gpg"             gpg            configs ""
    _t "$HOME/.password-store"  password-store configs ""
    _t "$HOME/.omp/agent"       omp            configs ""
    _t "$HOME/Pictures"         media          ""      ""
    # _t "$ZEN_DIR"              zen            configs ""
end

# --- Бэкап ---

function main_backup
    echo "Запуск скрипта бэкапа Restic..."
    init_repo
    define_targets

    set -l error_count 0

    for i in (seq (count $T_PATHS))
        set -l path $T_PATHS[$i]
        set -l tag_args --tag $T_SRCTAG[$i]
        test -n "$T_CATTAG[$i]"; and set -a tag_args --tag $T_CATTAG[$i]
        # восстановить excludes-массив из склеенной строки; пустая строка → без аргументов
        set -l excl
        test -n "$T_EXCL[$i]"; and set excl (string split ' ' -- $T_EXCL[$i])
        run_backup "$path" $tag_args $excl; or set error_count (math $error_count + 1)
    end

    echo "=== Выполнение задач завершено ==="
    echo "Запуск очистки (forget/prune)..."
    restic forget --prune --group-by tag --keep-last 2 --tag data
    restic forget --prune --group-by tag --keep-last 2 --tag configs
    restic forget --prune --group-by tag --keep-last 2 --tag media

    if test $error_count -gt 0
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    end
end

# --- Cleanup устаревших снимков ---

function main_cleanup
    set -l apply false
    if contains -- --apply $argv
        set apply true
    end

    define_targets

    # Активные тег-множества как JSON-массив массивов: [["projects","data"],["kube","configs"],...,["media"]]
    set -l quoted
    for i in (seq (count $T_SRCTAG))
        set -l tags $T_SRCTAG[$i]
        test -n "$T_CATTAG[$i]"; and set -a tags $T_CATTAG[$i]
        set -l qtags
        for t in $tags
            set -a qtags '"'$t'"'
        end
        set -a quoted '['(string join ',' -- $qtags)']'
    end
    set -l active_json '['(string join ',' -- $quoted)']'

    echo "Поиск устаревших снимков (host: "(hostname)")..."
    set -l stale_ids (restic snapshots --json --host (hostname) $RESTIC_COMMON_ARGS \
        | jq --argjson sets "$active_json" -r '
            ($sets | map(sort)) as $ss
            | .[]
            | select((.tags | sort) as $ts | ($ss | any(. == $ts)) | not)
            | .short_id
          ')

    if test (count $stale_ids) -eq 0
        echo "✅ Устаревших снимков не найдено."
        return 0
    end

    echo "Найдено "(count $stale_ids)" устаревших снимков:"
    printf '  %s\n' $stale_ids

    if not $apply
        echo ""
        echo "🔍 DRY-RUN (ничего не удаляется). Превью forget:"
        restic forget $stale_ids --dry-run --prune $RESTIC_COMMON_ARGS
        echo ""
        echo "Для реального удаления запустите: "(status current-command)" cleanup --apply"
        return 0
    end

    echo ""
    echo "⏳ forget + prune..."
    restic forget $stale_ids --prune $RESTIC_COMMON_ARGS
    or begin; echo "❌ ОШИБКА при forget/prune"; return 1; end

    echo ""
    echo "🔍 Проверка целостности репозитория (restic check)..."
    restic check $RESTIC_COMMON_ARGS
    or begin; echo "❌ ОШИБКА: restic check не прошёл"; return 1; end

    echo "🎉 Cleanup завершён."
    return 0
end

# --- Диспетчер ---

switch $argv[1]
    case cleanup
        main_cleanup $argv[2..]
    case '*'
        main_backup
end
