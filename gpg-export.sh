#!/bin/bash

# Директория для сохранения ключей
EXPORT_DIR="$HOME/.gpg"

# --- Проверки ---
# Проверяем, установлена ли утилита gpg
if ! command -v gpg &> /dev/null; then
    echo "Ошибка: утилита gpg не найдена. Установите её сначала."
    exit 1
fi

# Создаем директорию для экспорта, если она не существует
mkdir -p "$EXPORT_DIR"

# Устанавливаем безопасные права на директорию (только для владельца)
chmod 700 "$EXPORT_DIR"

echo "Экспорт GPG ключей в директорию: $EXPORT_DIR"
echo "------------------------------------------------"

# --- Экспорт публичных ключей ---
echo "Экспорт публичных ключей..."
# Получаем список всех ID публичных ключей
PUBLIC_KEYS=$(gpg --list-public-keys --keyid-format LONG | grep ^pub | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$PUBLIC_KEYS" ]; then
    echo "  Не найдено публичных ключей для экспорта."
else
    for KEY_ID in $PUBLIC_KEYS; do
        echo "  -> Экспортирую публичный ключ: $KEY_ID"
        # Экспортируем ключ в ASCII-формате в файл
        gpg --armor --output "$EXPORT_DIR/public_${KEY_ID}.asc" --export "$KEY_ID"
        # Устанавливаем безопасные права на файл
        chmod 600 "$EXPORT_DIR/public_${KEY_ID}.asc"
    done
fi
echo "Публичные ключи экспортированы."


# --- Экспорт секретных (приватных) ключей ---
echo ""
echo "Экспорт секретных ключей..."
# Получаем список всех ID секретных ключей
SECRET_KEYS=$(gpg --list-secret-keys --keyid-format LONG | grep ^sec | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$SECRET_KEYS" ]; then
    echo "  Не найдено секретных ключей для экспорта."
else
    for KEY_ID in $SECRET_KEYS; do
        echo "  -> Экспортирую секретный ключ: $KEY_ID"
        # Экспортируем секретный ключ в ASCII-формате в файл
        gpg --armor --output "$EXPORT_DIR/secret_${KEY_ID}.asc" --export-secret-keys "$KEY_ID"
        # Устанавливаем безопасные права на файл
        chmod 600 "$EXPORT_DIR/secret_${KEY_ID}.asc"
    done
fi
echo "Секретные ключи экспортированы."

# --- Экспорт trust database ---
echo ""
echo "Экспорт базы данных доверия (ownertrust)..."
# Эта информация важна для восстановления уровня доверия к ключам
gpg --export-ownertrust > "$EXPORT_DIR/ownertrust.txt"
chmod 600 "$EXPORT_DIR/ownertrust.txt"
echo "База данных доверия экспортирована."

echo "------------------------------------------------"
echo "Экспорт успешно завершен!"
echo "Проверьте директорию: $EXPORT_DIR"
