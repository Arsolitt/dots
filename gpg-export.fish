#!/usr/bin/env fish

# Директория для сохранения ключей
set -l export_dir "$HOME/.gpg"

# --- Проверки ---
if not command --query gpg
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
end

# Создаем директорию для экспорта, если она не существует
mkdir -p "$export_dir"

# Устанавливаем безопасные права на директорию (только для владельца)
chmod 700 "$export_dir"

echo "Экспорт GPG ключей в директорию: $export_dir"
echo "------------------------------------------------"

# --- Экспорт публичных ключей ---
echo "Экспорт публичных ключей..."
# Получаем список всех ID публичных ключей
set -l public_keys (gpg --list-public-keys --keyid-format LONG 2>/dev/null | string match --regex '^pub' | awk '{print $2}' | cut -d'/' -f2)

if test -z "$public_keys"
    echo "  Не найдено публичных ключей для экспорта."
else
    for key_id in $public_keys
        echo "  -> Экспортирую публичный ключ: $key_id"
        # Экспортируем ключ в ASCII-формате в файл
        gpg --armor --output "$export_dir/public_$key_id.asc" --export "$key_id"
        # Устанавливаем безопасные права на файл
        chmod 600 "$export_dir/public_$key_id.asc"
    end
end
echo "Публичные ключи экспортированы."

# --- Экспорт секретных (приватных) ключей ---
echo ""
echo "Экспорт секретных ключей..."
# Получаем список всех ID секретных ключей
set -l secret_keys (gpg --list-secret-keys --keyid-format LONG 2>/dev/null | string match --regex '^sec' | awk '{print $2}' | cut -d'/' -f2)

if test -z "$secret_keys"
    echo "  Не найдено секретных ключей для экспорта."
else
    for key_id in $secret_keys
        echo "  -> Экспортирую секретный ключ: $key_id"
        # Экспортируем секретный ключ в ASCII-формате в файл
        gpg --armor --output "$export_dir/secret_$key_id.asc" --export-secret-keys "$key_id"
        # Устанавливаем безопасные права на файл
        chmod 600 "$export_dir/secret_$key_id.asc"
    end
end
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
