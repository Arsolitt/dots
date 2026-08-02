#!/usr/bin/env zsh

# fish's `for file in "$dir"/*.asc` silently iterates zero times when no
# files match; zsh aborts with "no matches found" by default. Match fish.
setopt NULL_GLOB

# Директория, откуда импортировать ключи
typeset import_dir="$HOME/.gpg"

# --- Проверки ---
if ! command -v gpg >/dev/null; then
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
fi

# Проверяем, существует ли директория с ключами
if [[ ! -d "$import_dir" ]]; then
    echo "Ошибка: директория для импорта не найдена: $import_dir"
    exit 1
fi

echo "Импорт GPG ключей из директории: $import_dir"
echo "------------------------------------------------"

# --- Импорт публичных ключей ---
echo "Импорт публичных ключей..."
# Находим все файлы публичных ключей и импортируем их
for file in "$import_dir"/public_*.asc; do
    if [[ -f "$file" ]]; then
        echo "  -> Импортирую файл: $(basename "$file")"
        gpg --import "$file"
    fi
done
echo "Публичные ключи импортированы."

# --- Импорт секретных (приватных) ключей ---
echo ""
echo "Импорт секретных ключей..."
# Находим все файлы секретных ключей и импортируем их
# GPG запросит парольную фразу для каждого ключа
for file in "$import_dir"/secret_*.asc; do
    if [[ -f "$file" ]]; then
        echo "  -> Импортирую файл: $(basename "$file")"
        gpg --import "$file"
    fi
done
echo "Секретные ключи импортированы."

# --- Импорт trust database ---
echo ""
echo "Восстановление базы данных доверия (ownertrust)..."
if [[ -f "$import_dir/ownertrust.txt" ]]; then
    gpg --import-ownertrust "$import_dir/ownertrust.txt"
    echo "База данных доверия восстановлена."
else
    echo "Файл ownertrust.txt не найден. Уровни доверия восстановлены не будут."
fi

echo "------------------------------------------------"
echo "Импорт успешно завершен!"

# Выводим список ключей для проверки
echo ""
echo "Проверьте список ваших ключей:"
echo "-----------------------------"
gpg --list-keys
