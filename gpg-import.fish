#!/usr/bin/env fish

# Директория, откуда импортировать ключи
set -l import_dir "$HOME/.gpg"

# --- Проверки ---
if not command --query gpg
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
end

# Проверяем, существует ли директория с ключами
if not test -d "$import_dir"
    echo "Ошибка: директория для импорта не найдена: $import_dir"
    exit 1
end

echo "Импорт GPG ключей из директории: $import_dir"
echo "------------------------------------------------"

# --- Импорт публичных ключей ---
echo "Импорт публичных ключей..."
# Находим все файлы публичных ключей и импортируем их
set -l pub_files "$import_dir"/public_*.asc
if test (count $pub_files) -eq 0
    echo "  Не найдено файлов публичных ключей для импорта."
else
    for file in $pub_files
        echo "  -> Импортирую файл: "(basename "$file")
        gpg --import "$file"
    end
    echo "Публичные ключи импортированы."
end

# Находим все файлы секретных ключей и импортируем их
# GPG запросит парольную фразу для каждого ключа
set -l sec_files "$import_dir"/secret_*.asc
if test (count $sec_files) -eq 0
    echo "  Не найдено файлов секретных ключей для импорта."
else
    for file in $sec_files
        echo "  -> Импортирую файл: "(basename "$file")
        gpg --import "$file"
    end
    echo "Секретные ключи импортированы."
end

# --- Импорт trust database ---
echo ""
echo "Восстановление базы данных доверия (ownertrust)..."
if test -f "$import_dir/ownertrust.txt"
    gpg --import-ownertrust "$import_dir/ownertrust.txt"
    echo "База данных доверия восстановлена."
else
    echo "Файл ownertrust.txt не найден. Уровни доверия восстановлены не будут."
end

echo "------------------------------------------------"
echo "Импорт успешно завершен!"

# Выводим список ключей для проверки
echo ""
echo "Проверьте список ваших ключей:"
echo "-----------------------------"
gpg --list-keys
