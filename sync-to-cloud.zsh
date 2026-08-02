#!/usr/bin/env zsh

# --- Зависимости ---
for cmd in restic pass jq; do
    command -v $cmd >/dev/null || { echo "Ошибка: $cmd не найден. Установите его сначала."; exit 1 }
done

# --- Платформа ---
case "$(uname -s)" in
    Darwin)
        ZEN_DIR="$HOME/Library/Application Support/zen"
        ;;
    *)
        ZEN_DIR="$HOME/.zen"
        ;;
esac

# --- Конфигурация ---
if [[ -z $RESTIC_REPOSITORY ]]; then
    export RESTIC_REPOSITORY="sftp:pbackup:/mnt/backup/restic"
fi

if [[ -z $RESTIC_PASSWORD_COMMAND ]]; then
    export RESTIC_PASSWORD_COMMAND="pass restic/backup-repo"
fi

RESTIC_COMMON_ARGS=(--verbose)

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
    --exclude="**/.stignore.*"
)

# --- Функции ---

init_repo() {
    echo "Проверка репозитория..."
    if ! restic snapshots $RESTIC_COMMON_ARGS >/dev/null 2>&1; then
        echo "Инициализация нового репозитория..."
        restic init
    fi
}

run_backup() {
    local src=$1
    local -a extra_args
    extra_args=("${(@)argv:2}")

    echo "--- Начинаю бэкап: $src ---"

    if restic backup "$src" $RESTIC_COMMON_ARGS $extra_args; then
        echo "✅ Успешно: $src"
        return 0
    else
        echo "❌ ОШИБКА при бэкапе: $src"
        return 1
    fi
}

# --- Реестр целей (единый источник истины для бэкапа и cleanup) ---
# path | source_tag | category_tag ("" если нет) | excludes (строка через пробел, БЕЗ пробелов внутри значений)

_t() {
    T_PATHS+=("$1")
    T_SRCTAG+=("$2")
    T_CATTAG+=("$3")
    T_EXCL+=("$4")
}

define_targets() {
    T_PATHS=()
    T_SRCTAG=()
    T_CATTAG=()
    T_EXCL=()

    _t "$HOME/projects/"        projects       data    "${PROJECT_EXCLUDES[*]}"
    _t "$HOME/.kube"            kube           configs "--exclude=cache"
    _t "$HOME/.talos"           talos          configs ""
    _t "$HOME/.ssh"             ssh            configs ""
    _t "$HOME/.docker"          docker         configs ""
    _t "$HOME/.gpg"             gpg            configs ""
    _t "$HOME/.password-store"  password-store configs ""
    _t "$HOME/.omp/agent"       omp            configs ""
    _t "$HOME/Pictures"         media          ""      ""
    # _t "$ZEN_DIR"              zen            configs ""
}

# --- Бэкап ---

main_backup() {
    echo "Запуск скрипта бэкапа Restic..."
    init_repo
    define_targets

    local error_count=0
    local i src_path tag_args excl

    for ((i = 1; i <= ${#T_PATHS[@]}; i++)); do
        src_path=${T_PATHS[$i]}
        tag_args=(--tag ${T_SRCTAG[$i]})
        [[ -n ${T_CATTAG[$i]} ]] && tag_args+=(--tag ${T_CATTAG[$i]})
        # восстановить excludes-массив из склеенной строки; пустая строка → без аргументов
        excl=()
        [[ -n ${T_EXCL[$i]} ]] && excl=(${(z)T_EXCL[$i]})
        run_backup "$src_path" $tag_args $excl || ((error_count++))
    done

    echo "=== Выполнение задач завершено ==="
    echo "Запуск очистки (forget/prune)..."
    restic forget --prune --group-by tag --keep-last 2 --tag data
    restic forget --prune --group-by tag --keep-last 2 --tag configs
    restic forget --prune --group-by tag --keep-last 2 --tag media

    if [[ $error_count -gt 0 ]]; then
        echo "⚠️ Всего ошибок: $error_count"
        exit 1
    else
        echo "🎉 Все бэкапы выполнены успешно!"
        exit 0
    fi
}

# --- Cleanup устаревших снимков ---

main_cleanup() {
    local apply=false
    if [[ " $@ " == *" --apply "* ]]; then
        apply=true
    fi

    define_targets

    # Активные тег-множества как JSON-массив массивов: [["projects","data"],["kube","configs"],...,["media"]]
    local -a quoted
    local i
    for ((i = 1; i <= ${#T_SRCTAG[@]}; i++)); do
        local -a tags=(${T_SRCTAG[$i]})
        [[ -n ${T_CATTAG[$i]} ]] && tags+=(${T_CATTAG[$i]})
        local -a qtags=()
        local t
        for t in "${tags[@]}"; do
            qtags+=("\"$t\"")
        done
        quoted+=("[$(IFS=,; echo "${qtags[*]}")]")
    done
    local active_json="[$(IFS=,; echo "${quoted[*]}")]"

    echo "Поиск устаревших снимков (host: $(hostname))..."
    local -a stale_ids=($(restic snapshots --json --host "$(hostname)" $RESTIC_COMMON_ARGS \
        | jq --argjson sets "$active_json" -r '
            ($sets | map(sort)) as $ss
            | .[]
            | select((.tags | sort) as $ts | ($ss | any(. == $ts)) | not)
            | .short_id
          '))

    if [[ ${#stale_ids[@]} -eq 0 ]]; then
        echo "✅ Устаревших снимков не найдено."
        return 0
    fi

    echo "Найдено ${#stale_ids[@]} устаревших снимков:"
    printf '  %s\n' "${stale_ids[@]}"

    if [[ $apply == false ]]; then
        echo ""
        echo "🔍 DRY-RUN (ничего не удаляется). Превью forget:"
        restic forget "${stale_ids[@]}" --dry-run --prune $RESTIC_COMMON_ARGS
        echo ""
        echo "Для реального удаления запустите: $0 cleanup --apply"
        return 0
    fi

    echo ""
    echo "⏳ forget + prune..."
    restic forget "${stale_ids[@]}" --prune $RESTIC_COMMON_ARGS \
        || { echo "❌ ОШИБКА при forget/prune"; return 1 }

    echo ""
    echo "🔍 Проверка целостности репозитория (restic check)..."
    restic check $RESTIC_COMMON_ARGS \
        || { echo "❌ ОШИБКА: restic check не прошёл"; return 1 }

    echo "🎉 Cleanup завершён."
    return 0
}

# --- Диспетчер ---

case $1 in
    cleanup)
        main_cleanup "${(@)argv:2}"
        ;;
    *)
        main_backup
        ;;
esac
