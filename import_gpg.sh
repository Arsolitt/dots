#!/bin/bash

# Директория, откуда импортировать ключи
IMPORT_DIR="$HOME/.gpg"

# --- Проверки ---
# Проверяем, установлена ли утилита gpg
if ! command -v gpg &> /dev/null; then
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
fi

# Проверяем, существует ли директория с ключами
if [ ! -d "$IMPORT_DIR" ]; then
    echo "Ошибка: директория для импорта не найдена: $IMPORT_DIR"
    exit 1
fi

echo "Импорт GPG ключей из директории: $IMPORT_DIR"
echo "------------------------------------------------"

# --- Импорт публичных ключей ---
echo "Импорт публичных ключей..."
# Находим все файлы публичных ключей и импортируем их
find "$IMPORT_DIR" -name "public_*.asc" -print0 | while IFS= read -r -d $'\0' file; do
    echo "  -> Импортирую файл: $(basename "$file")"
    gpg --import "$file"
done
echo "Публичные ключи импортированы."

# --- Импорт секретных (приватных) ключей ---
echo ""
echo "Импорт секретных ключей..."
# Находим все файлы секретных ключей и импортируем их
# GPG запросит парольную фразу для каждого ключа
find "$IMPORT_DIR" -name "secret_*.asc" -print0 | while IFS= read -r -d $'\0' file; do
    echo "  -> Импортирую файл: $(basename "$file")"
    gpg --import "$file"
done
echo "Секретные ключи импортированы."

# --- Импорт trust database ---
echo ""
echo "Восстановление базы данных доверия (ownertrust)..."
if [ -f "$IMPORT_DIR/ownertrust.txt" ]; then
    gpg --import-ownertrust "$IMPORT_DIR/ownertrust.txt"
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
