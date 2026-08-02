#!/usr/bin/env zsh

# fish's `for file in "$dir"/*.asc` silently iterates zero times when no
# files match; zsh aborts with "no matches found" by default. Match fish.
setopt NULL_GLOB

# Директория для сохранения ключей
typeset export_dir="$HOME/.gpg"

# --- Проверки ---
if ! command -v gpg >/dev/null; then
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
fi

# Создаем директорию для экспорта, если она не существует
mkdir -p "$export_dir"

# Устанавливаем безопасные права на директорию (только для владельца)
chmod 700 "$export_dir"

echo "Экспорт GPG ключей в директорию: $export_dir"
echo "------------------------------------------------"

# --- Экспорт публичных ключей ---
echo "Экспорт публичных ключей..."
# Получаем список всех ID публичных ключей
typeset -a public_keys
public_keys=("${(f)$(gpg --list-public-keys --keyid-format LONG 2>/dev/null | grep '^pub' | awk '{print $2}' | cut -d'/' -f2)}")
# "${(f)$(...)}" yields a 1-element array holding an empty string when the
# command outputs nothing; normalize to empty so the count check works.
(( ${#public_keys[@]} == 1 )) && [[ -z "${public_keys[1]}" ]] && public_keys=()

if (( ${#public_keys[@]} == 0 )); then
    echo "  Не найдено публичных ключей для экспорта."
else
    for key_id in "${public_keys[@]}"; do
        echo "  -> Экспортирую публичный ключ: $key_id"
        # Экспортируем ключ в ASCII-формате в файл
        gpg --armor --output "$export_dir/public_$key_id.asc" --export "$key_id"
        # Устанавливаем безопасные права на файл
        chmod 600 "$export_dir/public_$key_id.asc"
    done
fi
echo "Публичные ключи экспортированы."

# --- Экспорт секретных (приватных) ключей ---
echo ""
echo "Экспорт секретных ключей..."
# Получаем список всех ID секретных ключей
typeset -a secret_keys
secret_keys=("${(f)$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep '^sec' | awk '{print $2}' | cut -d'/' -f2)}")
(( ${#secret_keys[@]} == 1 )) && [[ -z "${secret_keys[1]}" ]] && secret_keys=()

if (( ${#secret_keys[@]} == 0 )); then
    echo "  Не найдено секретных ключей для экспорта."
else
    for key_id in "${secret_keys[@]}"; do
        echo "  -> Экспортирую секретный ключ: $key_id"
        # Экспортируем секретный ключ в ASCII-формате в файл
        gpg --armor --output "$export_dir/secret_$key_id.asc" --export-secret-keys "$key_id"
        # Устанавливаем безопасные права на файл
        chmod 600 "$export_dir/secret_$key_id.asc"
    done
fi
echo "Секретные ключи экспортированы."

# --- Экспорт trust database ---
echo ""
echo "Экспорт базы данных доверия (ownertrust)..."
# Эта информация важна для восстановления уровня доверия к ключам
gpg --export-ownertrust >"$export_dir/ownertrust.txt"
chmod 600 "$export_dir/ownertrust.txt"
echo "База данных доверия экспортирована."

echo "------------------------------------------------"
echo "Экспорт успешно завершен!"
echo "Проверьте директорию: $export_dir"
